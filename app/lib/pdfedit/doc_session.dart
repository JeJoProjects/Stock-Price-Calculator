/// One open PDF being edited: working file versions, live overlay edits,
/// undo/redo history, drafts and saving.
///
/// Model: the *working file* only changes through page-level actions
/// (delete/rotate/insert/move). Everything else is an overlay [EditOp] that is
/// baked into PDF content only when saving. A structural action first bakes
/// the current overlays (so page/object indices stay valid), then rewrites the
/// file. History is a list of snapshots `(versionIndex, ops)`; undo/redo just
/// move a pointer and swap the working version.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'edit_model.dart';
import 'pdf_baker.dart';
import 'pdfium_edit.dart';
import 'pdfium_worker.dart';

class _Snap {
  const _Snap(this.version, this.ops);
  final int version;
  final List<EditOp> ops;
}

class _Checkpoint {
  const _Checkpoint(this.bakedOps, this.action);
  final List<EditOp> bakedOps;
  final StructAction action;
}

/// Display size (points) of every page of [bytes].
List<(double, double)> readPageSizes(Uint8List bytes) {
  final doc = PdfiumDoc.openBytes(bytes);
  try {
    return [
      for (var i = 0; i < doc.pageCount; i++)
        () {
          final p = doc.loadPage(i);
          final s = (p.displayWidth, p.displayHeight);
          p.close();
          return s;
        }(),
    ];
  } finally {
    doc.close();
  }
}

class PdfDocSession extends ChangeNotifier {
  PdfDocSession._(this.title, this.sourcePath, Uint8List source, List<(double, double)> sizes)
      : _versions = [source],
        _pageSizes = sizes {
    _history = [const _Snap(0, [])];
    _savedSnap = _history.first;
  }

  /// File name shown in the document list.
  final String title;

  /// Original file (null for a new blank document).
  final String? sourcePath;

  /// Where Save writes (set after the first Save as).
  String? savedPath;

  final List<Uint8List> _versions;
  final List<_Checkpoint> _checkpoints = [];
  List<(double, double)> _pageSizes;
  late List<_Snap> _history;
  int _pos = 0;
  late _Snap _savedSnap;
  int _idCounter = 0;
  int _revision = 0;
  final _pageInfoCache = <String, Future<PageInfo>>{};

  /// Opens [path]. Throws [PdfiumException] for unreadable/encrypted files.
  static Future<PdfDocSession> open(String path) async {
    final bytes = await File(path).readAsBytes();
    final sizes = await PdfiumWorker.instance.run(() => readPageSizes(bytes));
    return PdfDocSession._(path.split(RegExp(r'[\\/]')).last, path, bytes, sizes);
  }

  static Future<PdfDocSession> blank({String title = 'Untitled.pdf', int pages = 1}) async {
    final bytes = await PdfiumWorker.instance.run(() => createBlankPdf(pages: pages));
    final sizes = await PdfiumWorker.instance.run(() => readPageSizes(bytes));
    return PdfDocSession._(title, null, bytes, sizes);
  }

  // -------------------------------------------------------------- state ---

  Uint8List get workingBytes => _versions[_snap.version];
  _Snap get _snap => _history[_pos];
  List<EditOp> get ops => List.unmodifiable(_snap.ops);
  int get pageCount => _pageSizes.length;
  (double, double) pageSize(int i) => _pageSizes[i];

  /// Increments whenever the working file changes (page images must reload).
  int get revision => _revision;

  bool get canUndo => _pos > 0;
  bool get canRedo => _pos < _history.length - 1;
  bool get dirty => !identical(_snap, _savedSnap);

  String newId() => 'e${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  List<EditOp> opsOnPage(int page) => [for (final o in _snap.ops) if (o.page == page) o];

  EditOp? opById(String id) {
    for (final o in _snap.ops) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Editable content of a page of the working file (cached per version).
  Future<PageInfo> pageInfo(int page) {
    final key = '${_snap.version}:$page';
    return _pageInfoCache.putIfAbsent(key, () async {
      final bytes = workingBytes;
      return (await analyzePagesAsync(bytes, [page])).single;
    });
  }

  // ------------------------------------------------------------ editing ---

  void _push(List<EditOp> ops, {int? version}) {
    final snap = _Snap(version ?? _snap.version, List.unmodifiable(ops));
    _history = [..._history.sublist(0, _pos + 1), snap];
    _pos = _history.length - 1;
    _trimVersions();
    notifyListeners();
  }

  void _trimVersions() {
    var maxV = 0;
    for (var i = 0; i <= _pos; i++) {
      if (_history[i].version > maxV) maxV = _history[i].version;
    }
    if (_versions.length > maxV + 1) {
      _versions.removeRange(maxV + 1, _versions.length);
      _checkpoints.removeRange(maxV, _checkpoints.length);
    }
  }

  void addOp(EditOp op) => _push([..._snap.ops, op]);

  void addOps(List<EditOp> ops) => _push([..._snap.ops, ...ops]);

  /// Replaces the op with the same id. With [record] false the change is shown
  /// but not added to history (use for drags, then call [commit]).
  void updateOp(EditOp op, {bool record = true}) {
    final list = [for (final o in _snap.ops) o.id == op.id ? op : o];
    if (record) {
      _push(list);
    } else {
      _history[_pos] = _Snap(_snap.version, List.unmodifiable(list));
      notifyListeners();
    }
  }

  /// Turns the current (unrecorded) state into one undo step: the state before
  /// the drag is restored from [before].
  void commit(List<EditOp> before) {
    final after = _snap.ops;
    _history[_pos] = _Snap(_snap.version, before);
    _push(after);
  }

  void removeOps(Iterable<String> ids) {
    final set = ids.toSet();
    if (!_snap.ops.any((o) => set.contains(o.id))) return;
    _push([for (final o in _snap.ops) if (!set.contains(o.id)) o]);
  }

  void undo() {
    if (!canUndo) return;
    final before = _snap.version;
    _pos--;
    _afterMove(before);
  }

  void redo() {
    if (!canRedo) return;
    final before = _snap.version;
    _pos++;
    _afterMove(before);
  }

  Future<void> _afterMove(int beforeVersion) async {
    if (_snap.version != beforeVersion) {
      final bytes = workingBytes;
      _pageSizes = await PdfiumWorker.instance.run(() => readPageSizes(bytes));
      _revision++;
    }
    notifyListeners();
  }

  // ----------------------------------------------------- structural ops ---

  /// Applies a page-level change. Pending overlays are baked first.
  Future<void> applyStructure(StructAction action) async {
    final ops = _snap.ops;
    final current = workingBytes;
    final result = await PdfiumWorker.instance.run(() => applyAction(bakeOps(current, ops), action));
    final sizes = await PdfiumWorker.instance.run(() => readPageSizes(result));
    final v = _snap.version;
    // Drop redo history, then extend the version chain.
    _history = _history.sublist(0, _pos + 1);
    _versions
      ..removeRange(v + 1, _versions.length)
      ..add(result);
    _checkpoints
      ..removeRange(v, _checkpoints.length)
      ..add(_Checkpoint(ops, action));
    _pageSizes = sizes;
    _revision++;
    _history.add(_Snap(v + 1, const []));
    _pos = _history.length - 1;
    notifyListeners();
  }

  // -------------------------------------------------------------- saving ---

  /// The finished PDF: overlays baked into the working file.
  Future<Uint8List> exportBytes() => bakeOpsAsync(workingBytes, _snap.ops);

  Future<void> saveTo(String path) async {
    final bytes = await exportBytes();
    await File(path).writeAsBytes(bytes, flush: true);
    savedPath = path;
    _savedSnap = _snap;
    notifyListeners();
  }

  // -------------------------------------------------------------- drafts ---

  /// Everything needed to resume later: the original file, every page-level
  /// change and the live overlays. (Does not embed the PDF itself.)
  Map<String, dynamic> toDraft() => {
        'format': 'stockcalc-pdfedit',
        'version': 1,
        'title': title,
        'source': sourcePath,
        'checkpoints': [
          for (final c in _checkpoints.sublist(0, _snap.version))
            {'ops': [for (final o in c.bakedOps) o.toJson()], 'action': c.action.toJson()},
        ],
        'ops': [for (final o in _snap.ops) o.toJson()],
      };

  Future<void> saveDraft(String path) => File(path).writeAsString(const JsonEncoder.withIndent(' ').convert(toDraft()));

  static Future<PdfDocSession> fromDraft(Map<String, dynamic> json) async {
    if (json['format'] != 'stockcalc-pdfedit') throw const FormatException('Not a PDF editor draft.');
    final source = json['source'] as String?;
    final PdfDocSession s;
    if (source == null) {
      s = await blank(title: json['title'] as String? ?? 'Untitled.pdf');
    } else {
      if (!File(source).existsSync()) throw FileSystemException('The original PDF is missing', source);
      s = await open(source);
    }
    for (final c in (json['checkpoints'] as List).cast<Map<String, dynamic>>()) {
      for (final o in (c['ops'] as List).cast<Map<String, dynamic>>()) {
        s._push([...s._snap.ops, EditOp.fromJson(o)]);
      }
      await s.applyStructure(StructAction.fromJson(c['action'] as Map<String, dynamic>));
    }
    final ops = [for (final o in (json['ops'] as List).cast<Map<String, dynamic>>()) EditOp.fromJson(o)];
    if (ops.isNotEmpty) s._push([...s._snap.ops, ...ops]);
    s._savedSnap = s._snap;
    return s;
  }

  static Future<PdfDocSession> openDraft(String path) async =>
      fromDraft(jsonDecode(await File(path).readAsString()) as Map<String, dynamic>);
}
