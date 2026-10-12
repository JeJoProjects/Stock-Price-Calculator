/// One long-lived isolate that runs *all* PDFium work (bake, analyse, page
/// actions, rendering) strictly one job at a time: PDFium is not thread-safe,
/// so concurrent short-lived isolates could corrupt shared state. The worker
/// also keeps recently opened documents warm for fast page rendering.
///
/// Note: the OCR tab's PDF text extraction uses `pdfrx`'s own worker; avoid
/// running a PDF OCR batch and heavy editing at the same moment.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'pdfium_edit.dart';

class PdfiumWorker {
  PdfiumWorker._();
  static final PdfiumWorker instance = PdfiumWorker._();

  /// Set before the first job to point the worker at a specific pdfium.dll.
  static String? dllPath;

  SendPort? _send;
  ReceivePort? _recv;
  Isolate? _isolate;
  Future<void>? _starting;
  final _pending = <int, Completer<Object?>>{};
  int _next = 0;

  /// Document keys the worker currently holds (so callers send bytes once).
  final _warm = <String>{};

  Future<void> _ensure() => _starting ??= _start();

  Future<void> _start() async {
    final recv = ReceivePort();
    _recv = recv;
    final ready = Completer<SendPort>();
    recv.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
        return;
      }
      final msg = m as List;
      final c = _pending.remove(msg[0] as int);
      if (c == null) return;
      if (msg[1] as bool) {
        final r = msg[2];
        c.complete(r is TransferableTypedData ? r.materialize().asUint8List() : r);
      } else {
        c.completeError(msg[3] == true ? PdfiumException(msg[2] as String) : StateError(msg[2] as String));
      }
    });
    _isolate = await Isolate.spawn(_entry, [recv.sendPort, dllPath]);
    _send = await ready.future;
  }

  /// Runs [job] inside the worker. [job] must only capture sendable values.
  Future<T> run<T>(T Function() job) async {
    await _ensure();
    final id = _next++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _send!.send([id, job]);
    return (await c.future) as T;
  }

  /// Renders page [index] of the document identified by [key] into BGRA pixels.
  /// [bytes] is only transmitted the first time a [key] is used.
  Future<Uint8List> render(String key, Uint8List bytes, int index, int w, int h, {bool annotations = true}) async {
    final send = _warm.add(key) ? bytes : null;
    try {
      return await run(() => renderCached(key, send, index, w, h, annotations));
    } on PdfiumException catch (e) {
      // The worker evicted the document from its warm cache: send it again.
      if (!e.message.contains('no longer loaded')) rethrow;
      return run(() => renderCached(key, bytes, index, w, h, annotations));
    }
  }

  /// Forgets a document (call when its version is replaced or it is closed).
  Future<void> release(String key) {
    if (!_warm.remove(key)) return Future.value();
    return run(() => releaseCached(key));
  }

  Future<void> dispose() async {
    _isolate?.kill(priority: Isolate.immediate);
    _recv?.close();
    _isolate = null;
    _send = null;
    _starting = null;
    _warm.clear();
  }
}

void _entry(List<Object?> init) {
  final main = init[0] as SendPort;
  PdfiumLib.overridePath = init[1] as String?;
  final rp = ReceivePort();
  main.send(rp.sendPort);
  rp.listen((msg) {
    final m = msg as List;
    final id = m[0] as int;
    try {
      final r = (m[1] as Function)();
      main.send([id, true, r is Uint8List ? TransferableTypedData.fromList([r]) : r]);
    } on PdfiumException catch (e) {
      main.send([id, false, e.message, true]);
    } on Object catch (e) {
      main.send([id, false, '$e', false]);
    }
  });
}

// Worker-side state (each isolate has its own copy of these statics).
final _openDocs = <String, PdfiumDoc>{};
const _maxOpenDocs = 6;

/// Renders from the worker's warm document cache. Must run inside the worker.
Uint8List renderCached(String key, Uint8List? bytes, int index, int w, int h, bool annotations) {
  var doc = _openDocs.remove(key);
  if (doc == null) {
    if (bytes == null) throw const PdfiumException('The document is no longer loaded; reopen it.');
    doc = PdfiumDoc.openBytes(bytes);
  }
  _openDocs[key] = doc; // most recently used last
  while (_openDocs.length > _maxOpenDocs) {
    final oldest = _openDocs.keys.first;
    _openDocs.remove(oldest)!.close();
  }
  final page = doc.loadPage(index);
  try {
    return page.renderBgra(w, h, annotations: annotations);
  } finally {
    page.close();
  }
}

void releaseCached(String key) => _openDocs.remove(key)?.close();
