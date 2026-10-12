/// Turns overlay edits into real PDF content (and applies page-level
/// changes) with PDFium. Everything here is synchronous and isolate-safe; the
/// `*Async` wrappers run it off the UI isolate.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'edit_model.dart';
import 'fonts.dart';
import 'pdfium_edit.dart';
import 'pdfium_worker.dart';

// ---------------------------------------------------------------------------
// Baking overlay edits
// ---------------------------------------------------------------------------

/// Returns [source] with [ops] written into the page content streams.
Uint8List bakeOps(Uint8List source, List<EditOp> ops) {
  if (ops.isEmpty) return source;
  final doc = PdfiumDoc.openBytes(source);
  try {
    final byPage = <int, List<EditOp>>{};
    for (final op in ops) {
      byPage.putIfAbsent(op.page, () => []).add(op);
    }
    for (final entry in byPage.entries) {
      if (entry.key < 0 || entry.key >= doc.pageCount) continue;
      final page = doc.loadPage(entry.key);
      try {
        _bakePage(doc, page, entry.value);
        page.generateContent();
      } finally {
        page.close();
      }
    }
    return doc.save();
  } finally {
    doc.close();
  }
}

Future<Uint8List> bakeOpsAsync(Uint8List source, List<EditOp> ops) =>
    ops.isEmpty ? Future.value(source) : PdfiumWorker.instance.run(() => bakeOps(source, ops));

void _bakePage(PdfiumDoc doc, PdfiumPage page, List<EditOp> ops) {
  final box = page.box;

  // 1. Deletions first: object indices refer to the file as opened.
  final remove = <int>{};
  for (final op in ops) {
    if (op is TextOp) remove.addAll(op.removeObjects);
    if (op is DeleteImageOp) remove.add(op.objectIndex);
  }
  if (remove.isNotEmpty) page.removeObjects(remove);

  // 2. Insertions in the order the user made them.
  (double, double) u(double x, double y) => box.toUser(x, y);
  List<(double, double)> boxPoly(Box b) => [u(b.l, b.t), u(b.r, b.t), u(b.r, b.b), u(b.l, b.b)];

  for (final op in ops) {
    switch (op) {
      case TextOp():
        final font = _font(doc, op.fontFamily, op.bold, op.italic, op.text);
        final lines = op.text.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].isEmpty) continue;
          final p = u(op.x, op.baselineY + i * op.size * 1.2);
          page.addText(lines[i], p.$1, p.$2, op.size, font, op.argb, upright: box.uprightMatrix);
        }
      case WhiteoutOp():
        page.addPolyline(boxPoly(op.box), fillArgb: op.argb, closed: true);
      case ShapeOp():
        _bakeShape(page, box, op);
      case MarkupOp():
        for (final r in op.rects) {
          switch (op.kind) {
            case MarkupKind.highlight:
              page.addPolyline(boxPoly(r), fillArgb: _withAlpha(op.argb, 0x66), closed: true);
            case MarkupKind.underline:
              page.addPolyline([u(r.l, r.b - 0.5), u(r.r, r.b - 0.5)], strokeArgb: op.argb, strokeWidth: 1);
            case MarkupKind.strikeout:
              page.addPolyline([u(r.l, r.cy), u(r.r, r.cy)], strokeArgb: op.argb, strokeWidth: 1);
          }
        }
      case InkOp():
        page.addPolyline(
          [for (final p in op.points) u(p.$1, p.$2)],
          strokeArgb: op.highlight ? _withAlpha(op.argb, 0x66) : op.argb,
          strokeWidth: op.width,
        );
      case ImageOp():
        _bakeImage(page, box, op);
      case SymbolOp():
        _bakeSymbol(page, box, op);
      case LinkOp():
        final a = u(op.box.l, op.box.t), c = u(op.box.r, op.box.b);
        page.addLink(math.min(a.$1, c.$1), math.min(a.$2, c.$2), math.max(a.$1, c.$1), math.max(a.$2, c.$2), op.uri);
      case DeleteImageOp():
        break; // handled in step 1
    }
  }
}

int _withAlpha(int argb, int alpha) => (alpha << 24) | (argb & 0xFFFFFF);

dynamic _font(PdfiumDoc doc, String family, bool bold, bool italic, String text) {
  final c = FontCatalog.resolve(family, bold, italic, text);
  return c.standardName != null ? doc.standardFont(c.standardName!) : doc.trueTypeFont(c.key, File(c.ttfPath!).readAsBytesSync());
}

void _bakeShape(PdfiumPage page, PageBox box, ShapeOp s) {
  (double, double) u(double x, double y) => box.toUser(x, y);
  switch (s.kind) {
    case ShapeKind.rectangle:
      final b = Box.fromCorners(s.x1, s.y1, s.x2, s.y2);
      page.addPolyline([u(b.l, b.t), u(b.r, b.t), u(b.r, b.b), u(b.l, b.b)],
          fillArgb: s.fillArgb, strokeArgb: s.strokeArgb, strokeWidth: s.width, closed: true);
    case ShapeKind.ellipse:
      final a = u(s.x1, s.y1), c = u(s.x2, s.y2);
      page.addEllipse(math.min(a.$1, c.$1), math.min(a.$2, c.$2), math.max(a.$1, c.$1), math.max(a.$2, c.$2),
          fillArgb: s.fillArgb, strokeArgb: s.strokeArgb, strokeWidth: s.width);
    case ShapeKind.line:
      page.addPolyline([u(s.x1, s.y1), u(s.x2, s.y2)], strokeArgb: s.strokeArgb, strokeWidth: s.width);
    case ShapeKind.arrow:
      page.addPolyline([u(s.x1, s.y1), u(s.x2, s.y2)], strokeArgb: s.strokeArgb, strokeWidth: s.width);
      final ang = math.atan2(s.y2 - s.y1, s.x2 - s.x1);
      final len = math.max(8.0, s.width * 4);
      (double, double) head(double da) => u(s.x2 - len * math.cos(ang + da), s.y2 - len * math.sin(ang + da));
      page.addPolyline([head(0.45), u(s.x2, s.y2), head(-0.45)], strokeArgb: s.strokeArgb, strokeWidth: s.width);
  }
}

void _bakeSymbol(PdfiumPage page, PageBox box, SymbolOp s) {
  (double, double) u(double x, double y) => box.toUser(x, y);
  final b = s.box;
  final w = math.max(1.0, math.min(b.w, b.h) * 0.14);
  switch (s.kind) {
    case SymbolKind.cross:
      page.addPolyline([u(b.l + b.w * .12, b.t + b.h * .12), u(b.r - b.w * .12, b.b - b.h * .12)], strokeArgb: s.argb, strokeWidth: w);
      page.addPolyline([u(b.r - b.w * .12, b.t + b.h * .12), u(b.l + b.w * .12, b.b - b.h * .12)], strokeArgb: s.argb, strokeWidth: w);
    case SymbolKind.check:
      page.addPolyline([u(b.l + b.w * .1, b.t + b.h * .55), u(b.l + b.w * .38, b.b - b.h * .12), u(b.r - b.w * .08, b.t + b.h * .12)],
          strokeArgb: s.argb, strokeWidth: w);
    case SymbolKind.square:
      page.addPolyline([u(b.l, b.t), u(b.r, b.t), u(b.r, b.b), u(b.l, b.b)], fillArgb: s.argb, closed: true);
    case SymbolKind.dot:
      final a = u(b.l, b.t), c = u(b.r, b.b);
      page.addEllipse(math.min(a.$1, c.$1), math.min(a.$2, c.$2), math.max(a.$1, c.$1), math.max(a.$2, c.$2), fillArgb: s.argb);
  }
}

void _bakeImage(PdfiumPage page, PageBox box, ImageOp op) {
  var image = img.decodeImage(op.data);
  if (image == null) return;
  if (image.width > 2400) image = img.copyResize(image, width: 2400, interpolation: img.Interpolation.average);
  final rot = box.rotation;
  if (rot != 0) image = img.copyRotate(image, angle: (360 - rot) % 360);
  image = image.convert(numChannels: 4, format: img.Format.uint8);
  final bgra = image.getBytes(order: img.ChannelOrder.bgra);
  final a = box.toUser(op.box.l, op.box.t), c = box.toUser(op.box.r, op.box.b);
  page.addImageBgra(Uint8List.fromList(bgra), image.width, image.height, math.min(a.$1, c.$1), math.min(a.$2, c.$2),
      math.max(a.$1, c.$1), math.max(a.$2, c.$2));
}

// ---------------------------------------------------------------------------
// Page-level (structural) changes
// ---------------------------------------------------------------------------

Uint8List applyAction(Uint8List bytes, StructAction action) {
  final doc = PdfiumDoc.openBytes(bytes);
  try {
    switch (action) {
      case DeletePages():
        final pages = action.pages.toSet().toList()..sort((a, b) => b.compareTo(a));
        if (pages.length >= doc.pageCount) throw const PdfiumException('A PDF needs at least one page.');
        for (final p in pages) {
          doc.deletePage(p);
        }
      case RotatePages():
        for (final i in action.pages) {
          final p = doc.loadPage(i);
          p.rotation = (p.rotation + action.degrees) % 360;
          p.close();
        }
      case InsertBlank():
        var w = action.width, h = action.height;
        if (w == null || h == null) {
          final ref = doc.loadPage(math.max(0, math.min(action.index - 1, doc.pageCount - 1)));
          final b = ref.box;
          w = b.w;
          h = b.h;
          ref.close();
        }
        doc.newPage(math.min(action.index, doc.pageCount), w, h).close();
      case InsertFromFile():
        final src = PdfiumDoc.openBytes(File(action.path).readAsBytesSync());
        try {
          doc.importPages(src, range: action.range, index: math.min(action.index, doc.pageCount));
        } finally {
          src.close();
        }
      case MovePage():
        if (action.from == action.to) break;
        final copy = PdfiumDoc.openBytes(bytes);
        try {
          doc.importPages(copy, range: '${action.from + 1}', index: action.to > action.from ? action.to + 1 : action.to);
        } finally {
          copy.close();
        }
        doc.deletePage(action.to > action.from ? action.from : action.from + 1);
    }
    return doc.save();
  } finally {
    doc.close();
  }
}

Future<Uint8List> applyActionAsync(Uint8List bytes, StructAction action) =>
    PdfiumWorker.instance.run(() => applyAction(bytes, action));

/// Creates a new blank PDF.
Uint8List createBlankPdf({int pages = 1, double width = 595.28, double height = 841.89}) {
  final d = PdfiumDoc.createBlank(pages: pages, width: width, height: height);
  try {
    return d.save();
  } finally {
    d.close();
  }
}

// ---------------------------------------------------------------------------
// Page analysis (what existing content can be edited)
// ---------------------------------------------------------------------------

class TextRunInfo {
  final int objectIndex;
  final String text;
  final Box box;
  final double originX, baselineY, fontSize;
  final String fontName;
  final bool bold, italic;
  final int argb;
  const TextRunInfo(this.objectIndex, this.text, this.box, this.originX, this.baselineY, this.fontSize, this.fontName,
      this.bold, this.italic, this.argb);
}

/// Adjacent runs on one baseline: the unit a user edits.
class TextLineInfo {
  final List<TextRunInfo> runs;
  const TextLineInfo(this.runs);

  Box get box => runs.map((r) => r.box).reduce((a, b) => a.union(b));
  String get text {
    final sb = StringBuffer();
    for (var i = 0; i < runs.length; i++) {
      if (i > 0) {
        final gap = runs[i].box.l - runs[i - 1].box.r;
        if (gap > runs[i].fontSize * 0.15 && !runs[i - 1].text.endsWith(' ') && !runs[i].text.startsWith(' ')) sb.write(' ');
      }
      sb.write(runs[i].text);
    }
    return sb.toString();
  }

  TextRunInfo get first => runs.first;
  List<int> get objectIndices => [for (final r in runs) r.objectIndex];
}

class PageImageInfo {
  final int objectIndex;
  final Box box;
  const PageImageInfo(this.objectIndex, this.box);
}

class PageInfo {
  final int index;
  final double width, height;
  final int rotation;
  final List<TextLineInfo> lines;
  final List<PageImageInfo> images;
  const PageInfo(this.index, this.width, this.height, this.rotation, this.lines, this.images);
}

Box _displayBox(PageBox pb, double l, double b, double r, double t) {
  final p1 = pb.toDisplay(l, t), p2 = pb.toDisplay(r, b);
  return Box.fromCorners(p1.$1, p1.$2, p2.$1, p2.$2);
}

/// Reads editable content (text lines, images) of the given pages.
List<PageInfo> analyzePages(Uint8List bytes, List<int> indices) {
  final doc = PdfiumDoc.openBytes(bytes);
  try {
    final out = <PageInfo>[];
    for (final i in indices) {
      if (i < 0 || i >= doc.pageCount) continue;
      final page = doc.loadPage(i);
      try {
        final pb = page.box;
        final runs = <TextRunInfo>[];
        for (final r in page.textRuns()) {
          final o = pb.toDisplay(r.originX, r.baselineY);
          runs.add(TextRunInfo(r.objectIndex, r.text, _displayBox(pb, r.left, r.bottom, r.right, r.top), o.$1, o.$2,
              r.fontSize, r.fontName, r.bold, r.italic, r.colorArgb));
        }
        final images = [for (final r in page.imageRuns()) PageImageInfo(r.objectIndex, _displayBox(pb, r.left, r.bottom, r.right, r.top))];
        out.add(PageInfo(i, pb.displayWidth, pb.displayHeight, pb.rotation, _groupLines(runs), images));
      } finally {
        page.close();
      }
    }
    return out;
  } finally {
    doc.close();
  }
}

Future<List<PageInfo>> analyzePagesAsync(Uint8List bytes, List<int> indices) =>
    PdfiumWorker.instance.run(() => analyzePages(bytes, indices));

/// Groups runs sharing a baseline into lines, splitting at wide gaps (columns).
List<TextLineInfo> _groupLines(List<TextRunInfo> runs) {
  final sorted = [...runs]..sort((a, b) {
      final dy = a.baselineY - b.baselineY;
      return dy.abs() > math.min(a.fontSize, b.fontSize) * 0.3 ? dy.sign.toInt() : a.box.l.compareTo(b.box.l);
    });
  final lines = <List<TextRunInfo>>[];
  for (final r in sorted) {
    List<TextRunInfo>? home;
    for (final l in lines.reversed.take(6)) {
      final last = l.last;
      if ((last.baselineY - r.baselineY).abs() <= math.min(last.fontSize, r.fontSize) * 0.3 &&
          r.box.l - last.box.r < r.fontSize * 0.8 &&
          r.box.l >= last.box.l - 1) {
        home = l;
        break;
      }
    }
    if (home != null) {
      home.add(r);
    } else {
      lines.add([r]);
    }
  }
  return [for (final l in lines) TextLineInfo(l)];
}
