import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/pdfedit/pdfium_edit.dart';

bool get _haveDll => File('build/windows/x64/runner/Release/pdfium.dll').existsSync();

void main() {
  const skip = 'needs pdfium.dll (build the Windows app once: setup_flutter.bat)';

  setUpAll(() {
    if (_haveDll) PdfiumLib.overridePath = File('build/windows/x64/runner/Release/pdfium.dll').absolute.path;
  });

  test('blank doc -> add text, shapes, image, link -> save -> reopen reads them back', () {
    final doc = PdfiumDoc.createBlank(pages: 2);
    final page = doc.loadPage(0);
    final font = doc.standardFont('Helvetica');
    page.addText('Kontostand 1.234,56 \u20AC', 72, 700, 18, font, 0xFF112233);
    page.addPolyline([(72, 600), (200, 600), (200, 650), (72, 650)], fillArgb: 0xFFFFC800, closed: true);
    page.addEllipse(250, 600, 350, 650, strokeArgb: 0xFFFF0000, strokeWidth: 2);
    final bgra = Uint8List.fromList(List.generate(4 * 4 * 4, (i) => i % 4 == 3 ? 255 : 200));
    page.addImageBgra(bgra, 4, 4, 400, 600, 450, 650);
    page.generateContent();
    page.close();
    final bytes = doc.save();
    doc.close();

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

    final re = PdfiumDoc.openBytes(bytes);
    expect(re.pageCount, 2);
    final p = re.loadPage(0);
    final runs = p.textRuns();
    expect(runs.map((r) => r.text), contains('Kontostand 1.234,56 \u20AC'));
    final r = runs.firstWhere((r) => r.text.startsWith('Kontostand'));
    expect(r.fontSize, closeTo(18, 0.01));
    expect(r.originX, closeTo(72, 0.5));
    expect(r.baselineY, closeTo(700, 0.5));
    expect(r.colorArgb & 0xFFFFFF, 0x112233);
    expect(p.imageRuns(), hasLength(1));
    p.close();
    re.close();
  }, skip: _haveDll ? false : skip);

  test('removing a text object and importing pages work', () {
    final doc = PdfiumDoc.createBlank();
    final page = doc.loadPage(0);
    page.addText('old', 50, 50, 12, doc.standardFont('Times-Roman'), 0xFF000000);
    page.addText('keep', 50, 80, 12, doc.standardFont('Times-Roman'), 0xFF000000);
    page.generateContent();
    final idx = page.textRuns().firstWhere((r) => r.text == 'old').objectIndex;
    page.removeObjects([idx]);
    page.generateContent();
    expect(page.textRuns().map((r) => r.text), ['keep']);
    page.close();

    final other = PdfiumDoc.createBlank(pages: 3);
    doc.importPages(other, range: '1-2', index: 1);
    expect(doc.pageCount, 3);
    doc.deletePage(0);
    expect(doc.pageCount, 2);
    other.close();
    doc.close();
  }, skip: _haveDll ? false : skip);

  test('link annotations and page geometry', () {
    final doc = PdfiumDoc.createBlank(width: 300, height: 400);
    final page = doc.loadPage(0);
    expect(page.addLink(10, 10, 100, 40, 'https://example.com'), isTrue);
    page.rotation = 90;
    final box = page.box;
    expect(box.rotation, 90);
    expect((box.displayWidth, box.displayHeight), (400.0, 300.0));
    // round trip display <-> user for every rotation
    for (final rot in [0, 90, 180, 270]) {
      final b = PageBox(0, 0, 300, 400, rot);
      final u = b.toUser(30, 50);
      final d = b.toDisplay(u.$1, u.$2);
      expect(d.$1, closeTo(30, 1e-9));
      expect(d.$2, closeTo(50, 1e-9));
    }
    page.close();
    doc.close();
  }, skip: _haveDll ? false : skip);
}
