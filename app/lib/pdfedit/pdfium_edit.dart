/// Thin FFI layer over PDFium's editing API (the same `pdfium.dll` that the
/// `pdfrx` package bundles for viewing). `pdfrx`'s generated bindings cover
/// viewing but lack the save call, so the ~50 functions an editor needs are
/// bound here directly.
///
/// PDFium is not thread-safe: use this layer from one isolate at a time (the
/// baker runs it inside `Isolate.run`). All coordinates are PDF user space
/// (points, origin bottom-left) unless a method says otherwise.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef Handle = Pointer<Void>;

final class _FileWrite extends Struct {
  @Int32()
  external int version;
  external Pointer<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Void>, UnsignedLong)>> writeBlock;
}

final class _FsMatrix extends Struct {
  @Float()
  external double a, b, c, d, e, f;
}

final class _FsRectF extends Struct {
  @Float()
  external double left, top, right, bottom;
}

/// Page object type ids (FPDF_PAGEOBJ_*).
abstract final class ObjType {
  static const text = 1, path = 2, image = 3, shading = 4, form = 5;
}

class PdfiumException implements Exception {
  final String message;
  const PdfiumException(this.message);
  @override
  String toString() => 'PdfiumException: $message';
}

/// Process-wide handle to the PDFium DLL (one per isolate).
class PdfiumLib {
  PdfiumLib._(this.lib) {
    lib.lookupFunction<Void Function(), void Function()>('FPDF_InitLibrary')();
  }

  /// Set before first use to force a specific DLL (tests, custom installs).
  static String? overridePath;
  static PdfiumLib? _instance;
  static PdfiumLib get instance => _instance ??= PdfiumLib._(DynamicLibrary.open(_locate()));

  final DynamicLibrary lib;

  static String _locate() {
    final candidates = <String>[
      ?overridePath,
      ?Platform.environment['PDFIUM_DLL'],
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}pdfium.dll',
      'build/windows/x64/runner/Release/pdfium.dll',
      'app/build/windows/x64/runner/Release/pdfium.dll',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return File(c).absolute.path;
    }
    return 'pdfium.dll';
  }

  /// Whether the DLL exports [name] (older PDFium builds lack some APIs).
  bool has(String name) => lib.providesSymbol(name);
}

/// Typed bindings. Kept in one class so a missing export fails with a clear
/// message at first use instead of at library load.
class _Api {
  _Api(DynamicLibrary l)
      : loadMem = l.lookupFunction<Handle Function(Pointer<Uint8>, Int32, Pointer<Utf8>),
            Handle Function(Pointer<Uint8>, int, Pointer<Utf8>)>('FPDF_LoadMemDocument'),
        createDoc = l.lookupFunction<Handle Function(), Handle Function()>('FPDF_CreateNewDocument'),
        closeDoc = l.lookupFunction<Void Function(Handle), void Function(Handle)>('FPDF_CloseDocument'),
        pageCount = l.lookupFunction<Int32 Function(Handle), int Function(Handle)>('FPDF_GetPageCount'),
        lastError = l.lookupFunction<UnsignedLong Function(), int Function()>('FPDF_GetLastError'),
        loadPage = l.lookupFunction<Handle Function(Handle, Int32), Handle Function(Handle, int)>('FPDF_LoadPage'),
        closePage = l.lookupFunction<Void Function(Handle), void Function(Handle)>('FPDF_ClosePage'),
        pageW = l.lookupFunction<Float Function(Handle), double Function(Handle)>('FPDF_GetPageWidthF'),
        pageH = l.lookupFunction<Float Function(Handle), double Function(Handle)>('FPDF_GetPageHeightF'),
        newPage = l.lookupFunction<Handle Function(Handle, Int32, Double, Double),
            Handle Function(Handle, int, double, double)>('FPDFPage_New'),
        deletePage = l.lookupFunction<Void Function(Handle, Int32), void Function(Handle, int)>('FPDFPage_Delete'),
        getRotation = l.lookupFunction<Int32 Function(Handle), int Function(Handle)>('FPDFPage_GetRotation'),
        setRotation = l.lookupFunction<Void Function(Handle, Int32), void Function(Handle, int)>('FPDFPage_SetRotation'),
        getMediaBox = l.lookupFunction<
            Int32 Function(Handle, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>),
            int Function(Handle, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>)>('FPDFPage_GetMediaBox'),
        getCropBox = l.lookupFunction<
            Int32 Function(Handle, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>),
            int Function(Handle, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>)>('FPDFPage_GetCropBox'),
        generate = l.lookupFunction<Int32 Function(Handle), int Function(Handle)>('FPDFPage_GenerateContent'),
        countObjects = l.lookupFunction<Int32 Function(Handle), int Function(Handle)>('FPDFPage_CountObjects'),
        getObject = l.lookupFunction<Handle Function(Handle, Int32), Handle Function(Handle, int)>('FPDFPage_GetObject'),
        removeObject = l.lookupFunction<Int32 Function(Handle, Handle), int Function(Handle, Handle)>('FPDFPage_RemoveObject'),
        insertObject = l.lookupFunction<Void Function(Handle, Handle), void Function(Handle, Handle)>('FPDFPage_InsertObject'),
        destroyObject = l.lookupFunction<Void Function(Handle), void Function(Handle)>('FPDFPageObj_Destroy'),
        objType = l.lookupFunction<Int32 Function(Handle), int Function(Handle)>('FPDFPageObj_GetType'),
        objBounds = l.lookupFunction<
            Int32 Function(Handle, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>),
            int Function(Handle, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>)>('FPDFPageObj_GetBounds'),
        objMatrix = l.lookupFunction<Int32 Function(Handle, Pointer<_FsMatrix>),
            int Function(Handle, Pointer<_FsMatrix>)>('FPDFPageObj_GetMatrix'),
        getFill = l.lookupFunction<
            Int32 Function(Handle, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>),
            int Function(Handle, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>)>('FPDFPageObj_GetFillColor'),
        loadTextPage = l.lookupFunction<Handle Function(Handle), Handle Function(Handle)>('FPDFText_LoadPage'),
        closeTextPage = l.lookupFunction<Void Function(Handle), void Function(Handle)>('FPDFText_ClosePage'),
        textObjGetText = l.lookupFunction<UnsignedLong Function(Handle, Handle, Pointer<Uint16>, UnsignedLong),
            int Function(Handle, Handle, Pointer<Uint16>, int)>('FPDFTextObj_GetText'),
        textObjFontSize = l.lookupFunction<Int32 Function(Handle, Pointer<Float>),
            int Function(Handle, Pointer<Float>)>('FPDFTextObj_GetFontSize'),
        textObjFont = l.lookupFunction<Handle Function(Handle), Handle Function(Handle)>('FPDFTextObj_GetFont'),
        fontBaseName = l.lookupFunction<UnsignedLong Function(Handle, Pointer<Utf8>, UnsignedLong),
            int Function(Handle, Pointer<Utf8>, int)>('FPDFFont_GetBaseFontName'),
        fontWeight = l.lookupFunction<Int32 Function(Handle), int Function(Handle)>('FPDFFont_GetWeight'),
        fontFlags = l.lookupFunction<Int32 Function(Handle), int Function(Handle)>('FPDFFont_GetFlags'),
        loadStdFont = l.lookupFunction<Handle Function(Handle, Pointer<Utf8>),
            Handle Function(Handle, Pointer<Utf8>)>('FPDFText_LoadStandardFont'),
        loadFont = l.lookupFunction<Handle Function(Handle, Pointer<Uint8>, Uint32, Int32, Int32),
            Handle Function(Handle, Pointer<Uint8>, int, int, int)>('FPDFText_LoadFont'),
        newTextObj = l.lookupFunction<Handle Function(Handle, Handle, Float),
            Handle Function(Handle, Handle, double)>('FPDFPageObj_CreateTextObj'),
        setText = l.lookupFunction<Int32 Function(Handle, Pointer<Uint16>),
            int Function(Handle, Pointer<Uint16>)>('FPDFText_SetText'),
        transform = l.lookupFunction<Void Function(Handle, Double, Double, Double, Double, Double, Double),
            void Function(Handle, double, double, double, double, double, double)>('FPDFPageObj_Transform'),
        setFill = l.lookupFunction<Int32 Function(Handle, Uint32, Uint32, Uint32, Uint32),
            int Function(Handle, int, int, int, int)>('FPDFPageObj_SetFillColor'),
        setStroke = l.lookupFunction<Int32 Function(Handle, Uint32, Uint32, Uint32, Uint32),
            int Function(Handle, int, int, int, int)>('FPDFPageObj_SetStrokeColor'),
        setStrokeWidth = l.lookupFunction<Int32 Function(Handle, Float), int Function(Handle, double)>('FPDFPageObj_SetStrokeWidth'),
        setLineCap = l.lookupFunction<Int32 Function(Handle, Int32), int Function(Handle, int)>('FPDFPageObj_SetLineCap'),
        setLineJoin = l.lookupFunction<Int32 Function(Handle, Int32), int Function(Handle, int)>('FPDFPageObj_SetLineJoin'),
        newPath = l.lookupFunction<Handle Function(Float, Float), Handle Function(double, double)>('FPDFPageObj_CreateNewPath'),
        moveTo = l.lookupFunction<Int32 Function(Handle, Float, Float), int Function(Handle, double, double)>('FPDFPath_MoveTo'),
        lineTo = l.lookupFunction<Int32 Function(Handle, Float, Float), int Function(Handle, double, double)>('FPDFPath_LineTo'),
        bezierTo = l.lookupFunction<Int32 Function(Handle, Float, Float, Float, Float, Float, Float),
            int Function(Handle, double, double, double, double, double, double)>('FPDFPath_BezierTo'),
        closePath = l.lookupFunction<Int32 Function(Handle), int Function(Handle)>('FPDFPath_Close'),
        drawMode = l.lookupFunction<Int32 Function(Handle, Int32, Int32), int Function(Handle, int, int)>('FPDFPath_SetDrawMode'),
        newImageObj = l.lookupFunction<Handle Function(Handle), Handle Function(Handle)>('FPDFPageObj_NewImageObj'),
        imageSetBitmap = l.lookupFunction<Int32 Function(Pointer<Handle>, Int32, Handle, Handle),
            int Function(Pointer<Handle>, int, Handle, Handle)>('FPDFImageObj_SetBitmap'),
        bitmapCreateEx = l.lookupFunction<Handle Function(Int32, Int32, Int32, Pointer<Uint8>, Int32),
            Handle Function(int, int, int, Pointer<Uint8>, int)>('FPDFBitmap_CreateEx'),
        bitmapDestroy = l.lookupFunction<Void Function(Handle), void Function(Handle)>('FPDFBitmap_Destroy'),
        saveAsCopy = l.lookupFunction<Int32 Function(Handle, Pointer<_FileWrite>, Uint32),
            int Function(Handle, Pointer<_FileWrite>, int)>('FPDF_SaveAsCopy'),
        importPages = l.lookupFunction<Int32 Function(Handle, Handle, Pointer<Utf8>, Int32),
            int Function(Handle, Handle, Pointer<Utf8>, int)>('FPDF_ImportPages'),
        createAnnot = l.lookupFunction<Handle Function(Handle, Int32), Handle Function(Handle, int)>('FPDFPage_CreateAnnot'),
        closeAnnot = l.lookupFunction<Void Function(Handle), void Function(Handle)>('FPDFPage_CloseAnnot'),
        annotSetRect = l.lookupFunction<Int32 Function(Handle, Pointer<_FsRectF>),
            int Function(Handle, Pointer<_FsRectF>)>('FPDFAnnot_SetRect'),
        annotSetUri = l.lookupFunction<Int32 Function(Handle, Pointer<Utf8>),
            int Function(Handle, Pointer<Utf8>)>('FPDFAnnot_SetURI');

  final Handle Function(Pointer<Uint8>, int, Pointer<Utf8>) loadMem;
  final Handle Function() createDoc;
  final void Function(Handle) closeDoc;
  final int Function(Handle) pageCount;
  final int Function() lastError;
  final Handle Function(Handle, int) loadPage;
  final void Function(Handle) closePage;
  final double Function(Handle) pageW, pageH;
  final Handle Function(Handle, int, double, double) newPage;
  final void Function(Handle, int) deletePage;
  final int Function(Handle) getRotation;
  final void Function(Handle, int) setRotation;
  final int Function(Handle, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>) getMediaBox, getCropBox;
  final int Function(Handle) generate;
  final int Function(Handle) countObjects;
  final Handle Function(Handle, int) getObject;
  final int Function(Handle, Handle) removeObject;
  final void Function(Handle, Handle) insertObject;
  final void Function(Handle) destroyObject;
  final int Function(Handle) objType;
  final int Function(Handle, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>) objBounds;
  final int Function(Handle, Pointer<_FsMatrix>) objMatrix;
  final int Function(Handle, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>) getFill;
  final Handle Function(Handle) loadTextPage;
  final void Function(Handle) closeTextPage;
  final int Function(Handle, Handle, Pointer<Uint16>, int) textObjGetText;
  final int Function(Handle, Pointer<Float>) textObjFontSize;
  final Handle Function(Handle) textObjFont;
  final int Function(Handle, Pointer<Utf8>, int) fontBaseName;
  final int Function(Handle) fontWeight;
  final int Function(Handle) fontFlags;
  final Handle Function(Handle, Pointer<Utf8>) loadStdFont;
  final Handle Function(Handle, Pointer<Uint8>, int, int, int) loadFont;
  final Handle Function(Handle, Handle, double) newTextObj;
  final int Function(Handle, Pointer<Uint16>) setText;
  final void Function(Handle, double, double, double, double, double, double) transform;
  final int Function(Handle, int, int, int, int) setFill, setStroke;
  final int Function(Handle, double) setStrokeWidth;
  final int Function(Handle, int) setLineCap, setLineJoin;
  final Handle Function(double, double) newPath;
  final int Function(Handle, double, double) moveTo, lineTo;
  final int Function(Handle, double, double, double, double, double, double) bezierTo;
  final int Function(Handle) closePath;
  final int Function(Handle, int, int) drawMode;
  final Handle Function(Handle) newImageObj;
  final int Function(Pointer<Handle>, int, Handle, Handle) imageSetBitmap;
  final Handle Function(int, int, int, Pointer<Uint8>, int) bitmapCreateEx;
  final void Function(Handle) bitmapDestroy;
  final int Function(Handle, Pointer<_FileWrite>, int) saveAsCopy;
  final int Function(Handle, Handle, Pointer<Utf8>, int) importPages;
  final Handle Function(Handle, int) createAnnot;
  final void Function(Handle) closeAnnot;
  final int Function(Handle, Pointer<_FsRectF>) annotSetRect;
  final int Function(Handle, Pointer<Utf8>) annotSetUri;
}

final _apis = <DynamicLibrary, _Api>{};
_Api _api() {
  final lib = PdfiumLib.instance.lib;
  return _apis.putIfAbsent(lib, () => _Api(lib));
}

/// One text run found on a page, in user space.
class TextRun {
  final int objectIndex;
  final String text;
  final double left, bottom, right, top;
  final double originX, baselineY;
  final double fontSize;
  final String fontName;
  final bool bold, italic;
  final int colorArgb;

  const TextRun({
    required this.objectIndex,
    required this.text,
    required this.left,
    required this.bottom,
    required this.right,
    required this.top,
    required this.originX,
    required this.baselineY,
    required this.fontSize,
    required this.fontName,
    required this.bold,
    required this.italic,
    required this.colorArgb,
  });
}

/// An image object found on a page, in user space.
class ImageRun {
  final int objectIndex;
  final double left, bottom, right, top;
  const ImageRun(this.objectIndex, this.left, this.bottom, this.right, this.top);
}

/// Crop box of a page in user space plus its /Rotate (0, 90, 180, 270).
class PageBox {
  final double left, bottom, right, top;
  final int rotation;
  const PageBox(this.left, this.bottom, this.right, this.top, this.rotation);
  double get w => right - left;
  double get h => top - bottom;

  /// Size as displayed (after rotation).
  double get displayWidth => rotation % 180 == 0 ? w : h;
  double get displayHeight => rotation % 180 == 0 ? h : w;

  /// Display point (origin top-left, y down) -> user-space point.
  (double, double) toUser(double dx, double dy) => switch (rotation) {
        90 => (left + dy, bottom + dx),
        180 => (left + w - dx, bottom + dy),
        270 => (left + w - dy, bottom + h - dx),
        _ => (left + dx, top - dy),
      };

  /// User-space point -> display point.
  (double, double) toDisplay(double ux, double uy) {
    final rx = ux - left, ry = uy - bottom;
    return switch (rotation) {
      90 => (ry, rx),
      180 => (w - rx, ry),
      270 => (h - ry, w - rx),
      _ => (rx, h - ry),
    };
  }

  /// Matrix (a,b,c,d) that makes upright display text for this rotation.
  (double, double, double, double) get uprightMatrix => switch (rotation) {
        90 => (0, 1, -1, 0),
        180 => (-1, 0, 0, -1),
        270 => (0, -1, 1, 0),
        _ => (1, 0, 0, 1),
      };
}

class PdfiumDoc {
  PdfiumDoc._(this.handle, this._mem);

  final Handle handle;
  final Pointer<Uint8>? _mem;
  bool _closed = false;
  final _fonts = <String, Handle>{};
  final _fontMem = <Pointer<Uint8>>[];

  /// Opens a PDF from memory (avoids Windows path/encoding problems).
  static PdfiumDoc openBytes(Uint8List bytes, {String? password}) {
    final a = _api();
    final mem = malloc<Uint8>(bytes.length);
    mem.asTypedList(bytes.length).setAll(0, bytes);
    final pw = password == null ? nullptr.cast<Utf8>() : password.toNativeUtf8();
    final h = a.loadMem(mem, bytes.length, pw);
    if (password != null) malloc.free(pw);
    if (h == nullptr) {
      malloc.free(mem);
      final err = a.lastError();
      throw PdfiumException(err == 4 ? 'Password required or wrong password.' : 'Cannot open PDF (PDFium error $err).');
    }
    return PdfiumDoc._(h, mem);
  }

  static PdfiumDoc createBlank({int pages = 1, double width = 595.28, double height = 841.89}) {
    final a = _api();
    final d = PdfiumDoc._(a.createDoc(), null);
    for (var i = 0; i < pages; i++) {
      d.newPage(i, width, height).close();
    }
    return d;
  }

  int get pageCount => _api().pageCount(handle);

  PdfiumPage loadPage(int index) {
    final p = _api().loadPage(handle, index);
    if (p == nullptr) throw PdfiumException('Cannot load page ${index + 1}.');
    return PdfiumPage._(this, p, index);
  }

  PdfiumPage newPage(int index, double width, double height) =>
      PdfiumPage._(this, _api().newPage(handle, index, width, height), index);

  void deletePage(int index) => _api().deletePage(handle, index);

  /// Copies [range] ("1,3,5-7", 1-based; null = all) of [src] in at [index].
  void importPages(PdfiumDoc src, {String? range, required int index}) {
    final r = range == null ? nullptr.cast<Utf8>() : range.toNativeUtf8();
    final ok = _api().importPages(handle, src.handle, r, index);
    if (range != null) malloc.free(r);
    if (ok == 0) throw const PdfiumException('Could not import pages.');
  }

  /// Loads (and caches per document) a standard-14 font by PDF name.
  Handle standardFont(String name) => _fonts.putIfAbsent('std:$name', () {
        final n = name.toNativeUtf8();
        final f = _api().loadStdFont(handle, n);
        malloc.free(n);
        if (f == nullptr) throw PdfiumException('Standard font "$name" is unavailable.');
        return f;
      });

  /// Embeds a TrueType font file (full Unicode via Identity-H) once per doc.
  Handle trueTypeFont(String key, Uint8List fontFile) => _fonts.putIfAbsent('ttf:$key', () {
        final mem = malloc<Uint8>(fontFile.length);
        mem.asTypedList(fontFile.length).setAll(0, fontFile);
        _fontMem.add(mem);
        final f = _api().loadFont(handle, mem, fontFile.length, 2, 1);
        if (f == nullptr) throw PdfiumException('Could not embed font "$key".');
        return f;
      });

  /// Serialises the document (full rewrite) to bytes.
  Uint8List save() {
    final a = _api();
    final chunks = BytesBuilder(copy: false);
    final cb = NativeCallable<Int32 Function(Pointer<Void>, Pointer<Void>, UnsignedLong)>.isolateLocal(
      (Pointer<Void> self, Pointer<Void> data, int size) {
        chunks.add(Uint8List.fromList(data.cast<Uint8>().asTypedList(size)));
        return 1;
      },
      exceptionalReturn: 0,
    );
    final fw = calloc<_FileWrite>();
    try {
      fw.ref.version = 1;
      fw.ref.writeBlock = cb.nativeFunction;
      if (a.saveAsCopy(handle, fw, 2) == 0) throw const PdfiumException('PDFium could not save the document.');
    } finally {
      cb.close();
      calloc.free(fw);
    }
    return chunks.toBytes();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _api().closeDoc(handle);
    final mem = _mem;
    if (mem != null) malloc.free(mem);
    for (final m in _fontMem) {
      malloc.free(m);
    }
  }
}

class PdfiumPage {
  PdfiumPage._(this.doc, this.handle, this.index);

  final PdfiumDoc doc;
  final Handle handle;
  final int index;

  double get displayWidth => _api().pageW(handle);
  double get displayHeight => _api().pageH(handle);

  int get rotation => _api().getRotation(handle) * 90;
  set rotation(int degrees) => _api().setRotation(handle, ((degrees ~/ 90) % 4 + 4) % 4);

  PageBox get box {
    final a = _api();
    final p = calloc<Float>(4);
    try {
      var ok = a.getCropBox(handle, p, p + 1, p + 2, p + 3);
      if (ok == 0) ok = a.getMediaBox(handle, p, p + 1, p + 2, p + 3);
      if (ok == 0) {
        return PageBox(0, 0, displayWidth, displayHeight, rotation);
      }
      return PageBox(p[0], p[1], p[2], p[3], rotation);
    } finally {
      calloc.free(p);
    }
  }

  int get objectCount => _api().countObjects(handle);

  /// Text runs (one per PDFium text object) with font info.
  List<TextRun> textRuns() {
    final a = _api();
    final runs = <TextRun>[];
    final tp = a.loadTextPage(handle);
    final f4 = calloc<Float>(4);
    final u4 = calloc<Uint32>(4);
    final m = calloc<_FsMatrix>();
    try {
      final n = a.countObjects(handle);
      for (var i = 0; i < n; i++) {
        final o = a.getObject(handle, i);
        if (o == nullptr || a.objType(o) != ObjType.text) continue;
        final bytes = a.textObjGetText(o, tp, nullptr.cast(), 0);
        if (bytes <= 2) continue;
        final buf = calloc<Uint16>(bytes ~/ 2 + 1);
        a.textObjGetText(o, tp, buf, bytes);
        final text = String.fromCharCodes(buf.asTypedList(bytes ~/ 2 - 1));
        calloc.free(buf);
        if (text.trim().isEmpty) continue;
        if (a.objBounds(o, f4, f4 + 1, f4 + 2, f4 + 3) == 0) continue;
        final left = f4[0], bottom = f4[1], right = f4[2], top = f4[3];
        var size = 12.0;
        if (a.textObjFontSize(o, f4) != 0) size = f4[0];
        var ox = left, by = bottom;
        if (a.objMatrix(o, m) != 0) {
          ox = m.ref.e;
          by = m.ref.f;
        }
        var name = '', bold = false, italic = false;
        try {
          final font = a.textObjFont(o);
          if (font != nullptr) {
            final nb = calloc<Uint8>(256).cast<Utf8>();
            a.fontBaseName(font, nb, 256);
            name = nb.toDartString();
            calloc.free(nb);
            final flags = a.fontFlags(font);
            bold = a.fontWeight(font) >= 600 || (flags & 0x40000) != 0 || RegExp('bold', caseSensitive: false).hasMatch(name);
            italic = (flags & 0x40) != 0 || RegExp('italic|oblique', caseSensitive: false).hasMatch(name);
          }
        } on Object {
          // Font details are best-effort.
        }
        var color = 0xFF000000;
        if (a.getFill(o, u4, u4 + 1, u4 + 2, u4 + 3) != 0) {
          color = (u4[3] << 24) | (u4[0] << 16) | (u4[1] << 8) | u4[2];
        }
        runs.add(TextRun(
          objectIndex: i,
          text: text,
          left: left,
          bottom: bottom,
          right: right,
          top: top,
          originX: ox,
          baselineY: by,
          fontSize: size.abs() < 1 ? (top - bottom) : size.abs(),
          fontName: name.contains('+') ? name.substring(name.indexOf('+') + 1) : name,
          bold: bold,
          italic: italic,
          colorArgb: color,
        ));
      }
    } finally {
      calloc.free(f4);
      calloc.free(u4);
      calloc.free(m);
      if (tp != nullptr) a.closeTextPage(tp);
    }
    return runs;
  }

  List<ImageRun> imageRuns() {
    final a = _api();
    final f4 = calloc<Float>(4);
    final out = <ImageRun>[];
    try {
      final n = a.countObjects(handle);
      for (var i = 0; i < n; i++) {
        final o = a.getObject(handle, i);
        if (o == nullptr || a.objType(o) != ObjType.image) continue;
        if (a.objBounds(o, f4, f4 + 1, f4 + 2, f4 + 3) == 0) continue;
        out.add(ImageRun(i, f4[0], f4[1], f4[2], f4[3]));
      }
    } finally {
      calloc.free(f4);
    }
    return out;
  }

  /// Removes page objects by index (any order) and destroys them.
  void removeObjects(Iterable<int> indices) {
    final a = _api();
    final sorted = indices.toSet().toList()..sort((x, y) => y.compareTo(x));
    for (final i in sorted) {
      final o = a.getObject(handle, i);
      if (o == nullptr) continue;
      if (a.removeObject(handle, o) != 0) a.destroyObject(o);
    }
  }

  /// Inserts a single line of text; [x],[y] is the baseline-left in user
  /// space. [upright] is the rotation matrix for rotated pages.
  void addText(
    String text,
    double x,
    double y,
    double size,
    Handle font,
    int argb, {
    (double, double, double, double) upright = (1, 0, 0, 1),
  }) {
    final a = _api();
    final obj = a.newTextObj(doc.handle, font, size);
    if (obj == nullptr) throw const PdfiumException('Could not create a text object.');
    final w = malloc<Uint16>(text.length + 1);
    for (var i = 0; i < text.length; i++) {
      w[i] = text.codeUnitAt(i);
    }
    w[text.length] = 0;
    final ok = a.setText(obj, w);
    malloc.free(w);
    if (ok == 0) {
      a.destroyObject(obj);
      throw const PdfiumException('Could not set text.');
    }
    _fillColor(obj, argb);
    a.transform(obj, upright.$1, upright.$2, upright.$3, upright.$4, x, y);
    a.insertObject(handle, obj);
  }

  void _fillColor(Handle obj, int argb) => _api().setFill(obj, (argb >> 16) & 255, (argb >> 8) & 255, argb & 255, (argb >> 24) & 255);

  /// Adds a path through [points] (user space). [fillArgb]/[strokeArgb] null =
  /// not painted. Closed paths can be filled.
  void addPolyline(
    List<(double, double)> points, {
    int? fillArgb,
    int? strokeArgb,
    double strokeWidth = 1,
    bool closed = false,
  }) {
    if (points.length < 2) return;
    final a = _api();
    final p = a.newPath(points.first.$1, points.first.$2);
    for (var i = 1; i < points.length; i++) {
      a.lineTo(p, points[i].$1, points[i].$2);
    }
    if (closed) a.closePath(p);
    _stylePath(p, fillArgb, strokeArgb, strokeWidth);
    a.insertObject(handle, p);
  }

  /// Adds an ellipse inscribed in the user-space rectangle.
  void addEllipse(double l, double b, double r, double t, {int? fillArgb, int? strokeArgb, double strokeWidth = 1}) {
    const k = 0.5522847498;
    final cx = (l + r) / 2, cy = (b + t) / 2, rx = (r - l) / 2, ry = (t - b) / 2;
    final a = _api();
    final p = a.newPath(cx + rx, cy);
    a.bezierTo(p, cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry);
    a.bezierTo(p, cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy);
    a.bezierTo(p, cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry);
    a.bezierTo(p, cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy);
    a.closePath(p);
    _stylePath(p, fillArgb, strokeArgb, strokeWidth);
    a.insertObject(handle, p);
  }

  void _stylePath(Handle p, int? fillArgb, int? strokeArgb, double strokeWidth) {
    final a = _api();
    if (fillArgb != null) _fillColor(p, fillArgb);
    if (strokeArgb != null) {
      a.setStroke(p, (strokeArgb >> 16) & 255, (strokeArgb >> 8) & 255, strokeArgb & 255, (strokeArgb >> 24) & 255);
      a.setStrokeWidth(p, strokeWidth);
      a.setLineCap(p, 1);
      a.setLineJoin(p, 1);
    }
    a.drawMode(p, fillArgb != null ? 1 : 0, strokeArgb != null ? 1 : 0);
  }

  /// Places a BGRA bitmap (width*height*4 bytes) into the user-space rect.
  void addImageBgra(Uint8List bgra, int width, int height, double l, double b, double r, double t) {
    final a = _api();
    final mem = malloc<Uint8>(bgra.length);
    mem.asTypedList(bgra.length).setAll(0, bgra);
    final bmp = a.bitmapCreateEx(width, height, 4, mem, width * 4);
    final obj = a.newImageObj(doc.handle);
    final pages = calloc<Handle>(1);
    pages[0] = handle;
    try {
      if (bmp == nullptr || obj == nullptr || a.imageSetBitmap(pages, 1, obj, bmp) == 0) {
        throw const PdfiumException('Could not add the image.');
      }
      // Image objects are unit squares; scale and translate into the rect.
      a.transform(obj, r - l, 0, 0, t - b, l, b);
      a.insertObject(handle, obj);
    } finally {
      calloc.free(pages);
      if (bmp != nullptr) a.bitmapDestroy(bmp);
      malloc.free(mem);
    }
  }

  /// Adds a clickable URI link over the user-space rect. Returns false when
  /// the PDFium build cannot create link annotations.
  bool addLink(double l, double b, double r, double t, String uri) {
    final a = _api();
    final annot = a.createAnnot(handle, 2);
    if (annot == nullptr) return false;
    final rect = calloc<_FsRectF>();
    final u = uri.toNativeUtf8();
    try {
      rect.ref
        ..left = l
        ..bottom = b
        ..right = r
        ..top = t;
      final ok = a.annotSetRect(annot, rect) != 0 && a.annotSetUri(annot, u) != 0;
      return ok;
    } finally {
      malloc.free(u);
      calloc.free(rect);
      a.closeAnnot(annot);
    }
  }

  /// Commits inserted/removed objects to the page content stream.
  void generateContent() {
    if (_api().generate(handle) == 0) throw const PdfiumException('Could not write page content.');
  }

  void close() => _api().closePage(handle);
}
