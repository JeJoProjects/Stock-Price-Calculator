import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'file_classifier.dart';
import 'ocr_models.dart';
import 'ocr_service.dart';

enum OcrItemStatus { pending, running, done, error }

/// One file in the batch. Mutated only by [OcrBatchController].
class OcrBatchItem {
  final String path;
  final String name;
  final bool deleteAfter;
  OcrItemStatus status = OcrItemStatus.pending;
  String text = '';
  List<String> warnings = const [];
  String? error;
  OcrErrorKind? errorKind;

  OcrBatchItem({required this.path, required this.name, this.deleteAfter = false});

  String get label => labelFromFileName(name);
}

/// "German A1 certificate-2021.png" -> "GermanA1Certificate2021";
/// "1.1 - 01.2022 - Jährliche Mitteilung.jpg" -> "1.1_01.2022JährlicheMitteilung".
/// Unicode letters are kept, and dotted numbers ("1.1") stay one token.
String labelFromFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
  final tokens = RegExp(r'[\p{L}\p{N}]+(?:\.\p{N}+)*', unicode: true)
      .allMatches(stem)
      .map((m) => m[0]!)
      .toList();
  if (tokens.isEmpty) return 'Untitled';
  final digit = RegExp(r'\p{N}', unicode: true);
  var out = '';
  for (final t in tokens) {
    final word = t[0].toUpperCase() + t.substring(1);
    if (out.isNotEmpty && digit.hasMatch(out[out.length - 1]) && digit.hasMatch(word[0])) {
      out += '_';
    }
    out += word;
  }
  return out;
}

/// Compares strings so "page2" sorts before "page10".
int naturalCompare(String a, String b) {
  final ra = RegExp(r'\d+|\D+').allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final rb = RegExp(r'\d+|\D+').allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < ra.length && i < rb.length; i++) {
    final x = ra[i], y = rb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return ra.length.compareTo(rb.length);
}

bool _isSupported(String path) => isSupportedPath(path) || isPdfPath(path);

/// Expands files and folders (recursively) into supported file paths, in
/// natural order within each input. [skipped] counts unsupported files.
Future<({List<String> files, int skipped})> expandInputs(List<String> inputs) async {
  final files = <String>[];
  var skipped = 0;
  for (final input in inputs) {
    if (FileSystemEntity.isDirectorySync(input)) {
      final found = <String>[];
      await for (final e in Directory(input).list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        if (_isSupported(e.path)) {
          found.add(e.path);
        } else {
          skipped++;
        }
      }
      found.sort(naturalCompare);
      files.addAll(found);
    } else if (_isSupported(input)) {
      files.add(input);
    } else {
      skipped++;
    }
  }
  return (files: files, skipped: skipped);
}

String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

/// Builds the single-file Markdown document: title, then one numbered
/// section per file with its text in a fenced block.
String buildOcrMarkdown({
  required String title,
  required List<OcrBatchItem> items,
  DateTime? generatedAt,
}) {
  final stamp = DateFormat('yyyy-MM-dd HH:mm').format(generatedAt ?? DateTime.now());
  final b = StringBuffer()
    ..writeln('# $title')
    ..writeln()
    ..writeln('*${items.length} file${items.length == 1 ? '' : 's'} - generated $stamp*')
    ..writeln()
    ..writeln('---')
    ..writeln()
    ..writeln('## PART 1: FULL OCR TEXT EXTRACTION (every word, every file)')
    ..writeln();

  final seen = <String, int>{};
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    var label = item.label;
    final n = (seen[label] ?? 0) + 1;
    seen[label] = n;
    if (n > 1) label = '$label ($n)';

    final body = switch (item.status) {
      OcrItemStatus.done => item.text.isEmpty ? '[No text found]' : item.text,
      OcrItemStatus.error => '[OCR failed: ${item.error ?? 'unknown error'}]',
      OcrItemStatus.running => '[OCR in progress]',
      OcrItemStatus.pending => '[Waiting for OCR]',
    };
    var longest = 0;
    for (final m in RegExp('`+').allMatches(body)) {
      if (m.end - m.start > longest) longest = m.end - m.start;
    }
    final fence = '`' * (longest < 3 ? 3 : longest + 1);

    b.writeln('### Document ${i + 1} - `$label`');
    b.writeln();
    for (final w in item.warnings) {
      b.writeln('> Note: $w');
    }
    if (item.warnings.isNotEmpty) b.writeln();
    b
      ..writeln(fence)
      ..writeln(body)
      ..writeln(fence)
      ..writeln()
      ..writeln('---')
      ..writeln();
  }
  return b.toString();
}

/// Owns the batch queue and runs OCR over it one file at a time, so the UI
/// can show per-file progress and the results accumulate in order.
class OcrBatchController extends ChangeNotifier {
  OcrService _service;
  final List<OcrBatchItem> items = [];
  String? notice;
  bool _draining = false;
  bool _disposed = false;
  int _pasteCounter = 0;

  OcrBatchController(this._service);

  OcrService get service => _service;

  /// The engine is resolved asynchronously at app start; when a usable one
  /// arrives, files that failed only because none existed are retried.
  set service(OcrService value) {
    _service = value;
    if (value.recognizer != null &&
        items.any((i) => i.errorKind == OcrErrorKind.engineUnavailable)) {
      retryFailed(onlyEngineUnavailable: true);
    }
  }

  bool get hasFailures => items.any((i) => i.status == OcrItemStatus.error);

  Future<void> retryFailed({bool onlyEngineUnavailable = false}) async {
    for (final i in items) {
      if (i.status != OcrItemStatus.error) continue;
      if (onlyEngineUnavailable && i.errorKind != OcrErrorKind.engineUnavailable) continue;
      if (i.deleteAfter && !File(i.path).existsSync()) continue;
      i.status = OcrItemStatus.pending;
      i.error = null;
      i.errorKind = null;
    }
    _notify();
    await _drain();
  }

  bool get isBusy => items.any((i) =>
      i.status == OcrItemStatus.pending || i.status == OcrItemStatus.running);
  int get finishedCount =>
      items.where((i) => i.status == OcrItemStatus.done || i.status == OcrItemStatus.error).length;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> addPaths(List<String> inputs) async {
    final expanded = await expandInputs(inputs);
    final known = items.map((i) => i.path).toSet();
    var dupes = 0;
    for (final path in expanded.files) {
      if (!known.add(path)) {
        dupes++;
        continue;
      }
      items.add(OcrBatchItem(path: path, name: _baseName(path)));
    }
    final parts = <String>[
      if (expanded.skipped > 0) 'Skipped ${expanded.skipped} unsupported file(s).',
      if (dupes > 0) 'Ignored $dupes file(s) already in the list.',
      if (expanded.files.isEmpty && expanded.skipped == 0) 'No supported files found.',
    ];
    notice = parts.isEmpty ? null : parts.join(' ');
    _notify();
    await _drain();
  }

  Future<void> addPastedImage(Uint8List bytes) async {
    _pasteCounter++;
    final name = 'PastedImage$_pasteCounter.png';
    final file = await File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'stockcalc_ocr_${DateTime.now().microsecondsSinceEpoch}_$name',
    ).writeAsBytes(bytes);
    items.add(OcrBatchItem(path: file.path, name: name, deleteAfter: true));
    notice = null;
    _notify();
    await _drain();
  }

  void remove(OcrBatchItem item) {
    if (item.status == OcrItemStatus.running) return;
    items.remove(item);
    _deleteTemp(item);
    _notify();
  }

  void clear() {
    for (final i in items) {
      _deleteTemp(i);
    }
    items.clear();
    notice = null;
    _notify();
  }

  void _deleteTemp(OcrBatchItem item) {
    if (item.deleteAfter) {
      try {
        File(item.path).deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (!_disposed) {
        final next = items.where((i) => i.status == OcrItemStatus.pending).firstOrNull;
        if (next == null) break;
        next.status = OcrItemStatus.running;
        _notify();
        try {
          final result = await _service.extract(File(next.path));
          next.text = result.text;
          next.warnings = result.warnings;
          next.status = OcrItemStatus.done;
        } on OcrException catch (e) {
          next.error = e.message;
          next.errorKind = e.kind;
          next.status = OcrItemStatus.error;
        } catch (e) {
          next.error = 'Something went wrong reading this file: $e';
          next.status = OcrItemStatus.error;
        }
        // Keep a pasted temp file around if it may be retried.
        if (next.status == OcrItemStatus.done) _deleteTemp(next);
        _notify();
      }
    } finally {
      _draining = false;
    }
  }

  String toMarkdown(String title) => buildOcrMarkdown(title: title, items: items);

  @override
  void dispose() {
    _disposed = true;
    for (final i in items) {
      _deleteTemp(i);
    }
    super.dispose();
  }
}
