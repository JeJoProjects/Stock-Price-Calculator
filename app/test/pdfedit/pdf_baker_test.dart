import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stockcalc/pdfedit/edit_model.dart';
import 'package:stockcalc/pdfedit/fonts.dart';
import 'package:stockcalc/pdfedit/pdf_baker.dart';
import 'package:stockcalc/pdfedit/pdfium_edit.dart';

bool get _haveDll => File('build/windows/x64/runner/Release/pdfium.dll').existsSync();
const _skip = 'needs pdfium.dll (build the Windows app once: setup_flutter.bat)';

/// A synthetic statement-like page: invented data only.
Uint8List samplePdf({int rotation = 0, int pages = 1}) {
  final doc = PdfiumDoc.createBlank(pages: pages);
  final p = doc.loadPage(0);
  final f = doc.standardFont('Helvetica');
  p.addText('Konto Beispiel', 72, 770, 20, f, 0xFF000000);
  p.addText('Kontostand', 72, 700, 14, f, 0xFF000000);
  p.addText('1.234,56 €', 146, 700, 14, f, 0xFF000000);
  p.addText('Zeile weiter unten', 72, 650, 12, f, 0xFF333333);
  p.generateContent();
  if (rotation != 0) p.rotation = rotation;
  p.close();
  final b = doc.save();
  doc.close();
  return b;
}

List<String> lineTexts(Uint8List bytes, [int page = 0]) =>
    analyzePages(bytes, [page]).single.lines.map((l) => l.text).toList();

int _count(Uint8List b) {
  final d = PdfiumDoc.openBytes(b);
  final n = d.pageCount;
  d.close();
  return n;
}

void main() {
  setUpAll(() {
    if (_haveDll) PdfiumLib.overridePath = File('build/windows/x64/runner/Release/pdfium.dll').absolute.path;
  });

  test('analysis groups runs on one baseline into an editable line, in display coordinates', () {
    final info = analyzePages(samplePdf(), [0]).single;
    expect(info.width, closeTo(595.28, 0.01));
    expect(info.height, closeTo(841.89, 0.01));
    final texts = info.lines.map((l) => l.text).toList();
    expect(texts, containsAll(['Konto Beispiel', 'Kontostand 1.234,56 €', 'Zeile weiter unten']));
    final l = info.lines.firstWhere((l) => l.text.startsWith('Kontostand'));
    // baseline 700 in user space = 841.89 - 700 in display space
    expect(l.first.baselineY, closeTo(841.89 - 700, 0.5));
    expect(l.first.fontSize, closeTo(14, 0.01));
  }, skip: _haveDll ? false : _skip);

  test('editing existing text replaces it (old gone from the file, new present)', () {
    final src = samplePdf();
    final line = analyzePages(src, [0]).single.lines.firstWhere((l) => l.text.startsWith('Kontostand'));
    final op = TextOp(
      id: 'a',
      page: 0,
      x: line.first.originX,
      baselineY: line.first.baselineY,
      text: 'Kontostand 9.999,00 €',
      size: line.first.fontSize,
      removeObjects: line.objectIndices,
    );
    final out = bakeOps(src, [op]);
    final texts = lineTexts(out);
    expect(texts, contains('Kontostand 9.999,00 €'));
    expect(texts.any((t) => t.contains('1.234,56')), isFalse, reason: 'old amount must be truly removed');
    expect(texts, contains('Konto Beispiel'));
  }, skip: _haveDll ? false : _skip);

  test('new text lands where the display point says, on every page rotation', () {
    for (final rot in [0, 90, 180, 270]) {
      final src = samplePdf(rotation: rot);
      final info = analyzePages(src, [0]).single;
      final out = bakeOps(src, [
        const TextOp(id: 't', page: 0, x: 100, baselineY: 200, text: 'MARK', size: 16),
      ]);
      final run = analyzePages(out, [0]).single.lines.expand((l) => l.runs).firstWhere((r) => r.text == 'MARK');
      expect(run.originX, closeTo(100, 1), reason: 'rot $rot x');
      expect(run.baselineY, closeTo(200, 1), reason: 'rot $rot y');
      expect(info.rotation, rot);
    }
  }, skip: _haveDll ? false : _skip);

  test('every op kind bakes without error and survives a reopen', () {
    final png = Uint8List.fromList(
        img.encodePng(img.Image(width: 8, height: 8, numChannels: 4)..clear(img.ColorRgba8(10, 20, 200, 128))));
    final src = samplePdf();
    final out = bakeOps(src, [
      const WhiteoutOp('w', 0, Box(50, 50, 150, 80)),
      const ShapeOp(id: 's1', page: 0, kind: ShapeKind.rectangle, x1: 60, y1: 100, x2: 160, y2: 140, fillArgb: 0x55FFFF00),
      const ShapeOp(id: 's2', page: 0, kind: ShapeKind.ellipse, x1: 200, y1: 100, x2: 300, y2: 140),
      const ShapeOp(id: 's3', page: 0, kind: ShapeKind.line, x1: 60, y1: 160, x2: 160, y2: 160),
      const ShapeOp(id: 's4', page: 0, kind: ShapeKind.arrow, x1: 200, y1: 160, x2: 300, y2: 190),
      const MarkupOp(id: 'm1', page: 0, kind: MarkupKind.highlight, rects: [Box(72, 130, 200, 150)], argb: 0xFFFFEB3B),
      const MarkupOp(id: 'm2', page: 0, kind: MarkupKind.underline, rects: [Box(72, 130, 200, 150)], argb: 0xFFFF0000),
      const MarkupOp(id: 'm3', page: 0, kind: MarkupKind.strikeout, rects: [Box(72, 130, 200, 150)], argb: 0xFFFF0000),
      const InkOp(id: 'i', page: 0, points: [(10, 10), (20, 30), (40, 20)], argb: 0xFF0000FF),
      ImageOp('im', 0, const Box(400, 100, 460, 160), png),
      const SymbolOp('y1', 0, SymbolKind.cross, Box(300, 300, 320, 320), 0xFF000000),
      const SymbolOp('y2', 0, SymbolKind.check, Box(330, 300, 350, 320), 0xFF000000),
      const SymbolOp('y3', 0, SymbolKind.square, Box(360, 300, 380, 320), 0xFF000000),
      const SymbolOp('y4', 0, SymbolKind.dot, Box(390, 300, 410, 320), 0xFF000000),
      const LinkOp('l', 0, Box(72, 130, 200, 150), 'https://example.com'),
    ]);
    expect(String.fromCharCodes(out.take(5)), '%PDF-');
    final info = analyzePages(out, [0]).single;
    expect(info.images, hasLength(1));
    expect(info.images.single.box.w, closeTo(60, 0.5));
    expect(lineTexts(out), contains('Konto Beispiel'));
  }, skip: _haveDll ? false : _skip);

  test('unicode text embeds a TrueType font and reads back (euro, umlauts, symbols)', () {
    final fonts = FontCatalog.availableFamilies();
    final fam = fonts.contains('Segoe UI') ? 'Segoe UI' : 'Arial';
    final out = bakeOps(samplePdf(), [
      TextOp(id: 'u', page: 0, x: 72, baselineY: 400, text: 'Größe € ✓ Ł', fontFamily: fam, size: 14),
    ]);
    expect(lineTexts(out).any((t) => t.contains('Größe €')), isTrue);
  }, skip: _haveDll ? false : _skip);

  test('structural actions: delete, rotate, insert blank, insert from file, move', () {
    var b = samplePdf(pages: 3);
    expect(_count(b), 3);
    b = applyAction(b, const InsertBlank(1));
    expect(_count(b), 4);
    b = applyAction(b, const DeletePages([0]));
    expect(_count(b), 3);
    b = applyAction(b, const RotatePages([0], 90));
    expect(analyzePages(b, [0]).single.rotation, 90);
    b = applyAction(b, const RotatePages([0], -90));
    expect(analyzePages(b, [0]).single.rotation, 0);

    final tmp = File('${Directory.systemTemp.path}${Platform.pathSeparator}ins_${DateTime.now().microsecondsSinceEpoch}.pdf')
      ..writeAsBytesSync(samplePdf(pages: 2));
    addTearDown(() => tmp.deleteSync());
    b = applyAction(b, InsertFromFile(1, tmp.path, '1'));
    expect(_count(b), 4);

    // mark pages by rotation, then move and check the order
    var m = samplePdf(pages: 3);
    m = applyAction(m, const RotatePages([0], 90));
    m = applyAction(m, const RotatePages([1], 180));
    m = applyAction(m, const MovePage(0, 2));
    final rots = analyzePages(m, [0, 1, 2]).map((p) => p.rotation).toList();
    expect(rots, [180, 0, 90]);
    expect(() => applyAction(samplePdf(), const DeletePages([0])), throwsA(isA<PdfiumException>()));
  }, skip: _haveDll ? false : _skip);

  test('drafts: ops round-trip through JSON', () {
    final ops = <EditOp>[
      const TextOp(id: '1', page: 0, x: 1, baselineY: 2, text: 'a\nb', removeObjects: [3, 4], cover: [Box(1, 2, 3, 4)]),
      const WhiteoutOp('2', 1, Box(1, 2, 3, 4)),
      const ShapeOp(id: '3', page: 0, kind: ShapeKind.arrow, x1: 1, y1: 2, x2: 3, y2: 4, fillArgb: 0xFF00FF00),
      const MarkupOp(id: '4', page: 0, kind: MarkupKind.strikeout, rects: [Box(1, 2, 3, 4)], argb: 5),
      const InkOp(id: '5', page: 0, points: [(1, 2), (3, 4)], argb: 6, highlight: true),
      ImageOp('6', 0, const Box(1, 2, 3, 4), Uint8List.fromList([1, 2, 3])),
      const SymbolOp('7', 0, SymbolKind.check, Box(1, 2, 3, 4), 7),
      const LinkOp('8', 0, Box(1, 2, 3, 4), 'https://x.y'),
      const DeleteImageOp('9', 0, 12, Box(1, 2, 3, 4)),
    ];
    final back = [for (final o in ops) EditOp.fromJson(o.toJson())];
    expect([for (final o in back) o.toJson().toString()], [for (final o in ops) o.toJson().toString()]);
    for (final a in <StructAction>[
      const DeletePages([1, 2]),
      const RotatePages([0], 90),
      const InsertBlank(2, 100, 200),
      const InsertFromFile(1, 'x.pdf', '1-2'),
      const MovePage(0, 3),
    ]) {
      expect(StructAction.fromJson(a.toJson()).toJson(), a.toJson());
    }
  });

  test('font catalog: standard fonts for Latin text, embedded TTF otherwise', () {
    expect(FontCatalog.resolve('Helvetica', true, false, 'abc').standardName, 'Helvetica-Bold');
    expect(FontCatalog.resolve('Times', false, true, 'abc €').standardName, 'Times-Italic');
    expect(FontCatalog.isWinAnsi('äöüß€'), isTrue);
    expect(FontCatalog.isWinAnsi('✓'), isFalse);
    expect(FontCatalog.guessFamily('ABCDEF+Arial-BoldMT'), 'Helvetica');
    expect(FontCatalog.guessFamily('TimesNewRomanPSMT'), 'Times');
    expect(FontCatalog.guessFamily('CourierNewPS'), 'Courier');
  });
}
