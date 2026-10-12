/// The set of open documents in the PDF Editor tab.
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'doc_session.dart';
import 'pdfium_edit.dart';

bool isPdfPath(String p) => p.toLowerCase().endsWith('.pdf');
bool isDraftPath(String p) => p.toLowerCase().endsWith('.pdfedit');

class OpenFailure {
  final String path;
  final String message;
  const OpenFailure(this.path, this.message);
}

class PdfWorkspace extends ChangeNotifier {
  final List<PdfDocSession> docs = [];
  int _active = -1;

  /// Failures from the last open call (shown to the user).
  List<OpenFailure> lastFailures = const [];

  int get activeIndex => _active;
  PdfDocSession? get active => _active >= 0 && _active < docs.length ? docs[_active] : null;

  void activate(int i) {
    if (i < 0 || i >= docs.length || i == _active) return;
    _active = i;
    notifyListeners();
  }

  /// Opens files and folders (recursively, PDFs and drafts only) in natural
  /// order. Already-open files are just activated.
  Future<void> openPaths(List<String> inputs) async {
    final paths = <String>[];
    for (final input in inputs) {
      if (FileSystemEntity.isDirectorySync(input)) {
        final found = <String>[];
        await for (final e in Directory(input).list(recursive: true, followLinks: false)) {
          if (e is File && (isPdfPath(e.path) || isDraftPath(e.path))) found.add(e.path);
        }
        found.sort(_naturalCompare);
        paths.addAll(found);
      } else if (isPdfPath(input) || isDraftPath(input)) {
        paths.add(input);
      }
    }
    final failures = <OpenFailure>[];
    int? firstNew;
    for (final path in paths) {
      final existing = docs.indexWhere((d) => d.sourcePath == path);
      if (existing >= 0) {
        firstNew ??= existing;
        continue;
      }
      try {
        final s = isDraftPath(path) ? await PdfDocSession.openDraft(path) : await PdfDocSession.open(path);
        docs.add(s);
        firstNew ??= docs.length - 1;
      } on PdfiumException catch (e) {
        failures.add(OpenFailure(path, e.message));
      } on Object catch (e) {
        failures.add(OpenFailure(path, '$e'));
      }
    }
    lastFailures = failures;
    if (firstNew != null) _active = firstNew;
    notifyListeners();
  }

  Future<void> newBlank() async {
    final n = docs.where((d) => d.sourcePath == null).length + 1;
    docs.add(await PdfDocSession.blank(title: n == 1 ? 'Untitled.pdf' : 'Untitled $n.pdf'));
    _active = docs.length - 1;
    notifyListeners();
  }

  void close(int i) {
    if (i < 0 || i >= docs.length) return;
    docs.removeAt(i).dispose();
    if (docs.isEmpty) {
      _active = -1;
    } else if (_active >= docs.length) {
      _active = docs.length - 1;
    } else if (i < _active) {
      _active--;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final d in docs) {
      d.dispose();
    }
    super.dispose();
  }
}

int _naturalCompare(String a, String b) {
  final ra = RegExp(r'\d+|\D+').allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final rb = RegExp(r'\d+|\D+').allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < ra.length && i < rb.length; i++) {
    final nx = int.tryParse(ra[i]), ny = int.tryParse(rb[i]);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : ra[i].compareTo(rb[i]);
    if (c != 0) return c;
  }
  return ra.length.compareTo(rb.length);
}
