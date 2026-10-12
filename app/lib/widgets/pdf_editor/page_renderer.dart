import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../pdfedit/doc_session.dart';
import '../../pdfedit/pdfium_worker.dart';

/// Rendered page bitmaps (via the PDFium worker), cached with an LRU budget.
class PageImageCache {
  PageImageCache._();
  static final PageImageCache instance = PageImageCache._();

  static const _budgetBytes = 400 * 1024 * 1024;

  final _images = <String, ui.Image>{}; // insertion order = LRU order
  final _loading = <String, Future<ui.Image>>{};
  int _bytes = 0;

  String _key(PdfDocSession s, int page, int w, bool annots) => '${s.renderKey}|$page|$w|$annots';

  /// A cached image of this page at exactly this width, if present.
  ui.Image? peek(PdfDocSession s, int page, int w, {bool annotations = true}) {
    final k = _key(s, page, w, annotations);
    final img = _images.remove(k);
    if (img != null) _images[k] = img;
    return img;
  }

  /// Any cached image of this page (other widths): used as a blurry
  /// placeholder while a sharper one renders.
  ui.Image? anySize(PdfDocSession s, int page, {bool annotations = true}) {
    final prefix = '${s.renderKey}|$page|';
    for (final k in _images.keys.toList().reversed) {
      if (k.startsWith(prefix) && k.endsWith('|$annotations')) return _images[k];
    }
    return null;
  }

  Future<ui.Image> get(PdfDocSession s, int page, int w, int h, {bool annotations = true}) {
    final k = _key(s, page, w, annotations);
    final hit = peek(s, page, w, annotations: annotations);
    if (hit != null) return Future.value(hit);
    return _loading.putIfAbsent(k, () async {
      try {
        final bytes = s.workingBytes;
        final px = await PdfiumWorker.instance.render(s.renderKey, bytes, page, w, h, annotations: annotations);
        final img = await _decode(px, w, h);
        _images[k] = img;
        _bytes += w * h * 4;
        _evict();
        return img;
      } finally {
        _loading.remove(k);
      }
    });
  }

  Future<ui.Image> _decode(Uint8List px, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.bgra8888, c.complete);
    return c.future;
  }

  void _evict() {
    while (_bytes > _budgetBytes && _images.length > 1) {
      final k = _images.keys.first;
      final img = _images.remove(k)!;
      _bytes -= img.width * img.height * 4;
      img.dispose();
    }
  }

  /// Drops everything cached for [s] (call when the document is closed).
  void evictDoc(PdfDocSession s) {
    final prefix = '${identityHashCode(s)}:';
    for (final k in _images.keys.where((k) => k.startsWith(prefix)).toList()) {
      final img = _images.remove(k)!;
      _bytes -= img.width * img.height * 4;
      img.dispose();
    }
    PdfiumWorker.instance.release(s.renderKey);
  }
}

/// Decoded user images (signatures, stamps, pictures) for the overlay painter.
class OverlayImageCache {
  OverlayImageCache._();
  static final OverlayImageCache instance = OverlayImageCache._();

  final _images = <int, ui.Image>{};
  final _pending = <int>{};

  /// Returns the decoded image or null while it is still decoding; [onReady]
  /// fires when it becomes available.
  ui.Image? get(Uint8List bytes, void Function() onReady) {
    final key = Object.hash(bytes.length, identityHashCode(bytes));
    final hit = _images[key];
    if (hit != null) return hit;
    if (_pending.add(key)) {
      ui.instantiateImageCodec(bytes).then((codec) => codec.getNextFrame()).then((f) {
        _images[key] = f.image;
        _pending.remove(key);
        onReady();
      }, onError: (Object _) {
        _pending.remove(key);
      });
    }
    return null;
  }
}
