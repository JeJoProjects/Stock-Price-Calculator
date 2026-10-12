import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/pdfedit/pdf_baker.dart';
import 'package:stockcalc/pdfedit/pdfium_edit.dart';
import 'package:stockcalc/pdfedit/pdfium_worker.dart';

bool get _haveDll => File('build/windows/x64/runner/Release/pdfium.dll').existsSync();
const _skip = 'needs pdfium.dll (build the Windows app once: setup_flutter.bat)';

Uint8List _page() {
  final doc = PdfiumDoc.createBlank(pages: 2, width: 200, height: 100);
  final p = doc.loadPage(0);
  // a big black block: easy to detect in pixels
  p.addPolyline([(20, 20), (120, 20), (120, 70), (20, 70)], fillArgb: 0xFF000000, closed: true);
  p.generateContent();
  p.close();
  final b = doc.save();
  doc.close();
  return b;
}

void main() {
  setUpAll(() {
    if (_haveDll) PdfiumWorker.dllPath = File('build/windows/x64/runner/Release/pdfium.dll').absolute.path;
  });
  tearDownAll(() => PdfiumWorker.instance.dispose());

  test('jobs run in the worker, in order, and errors keep their type', () async {
    final w = PdfiumWorker.instance;
    final results = await Future.wait([for (var i = 0; i < 20; i++) w.run(() => i * 2)]);
    expect(results, [for (var i = 0; i < 20; i++) i * 2]);
    await expectLater(w.run<int>(() => throw const PdfiumException('boom')), throwsA(isA<PdfiumException>()));
    expect(await w.run(() => 7), 7, reason: 'the worker survives a failed job');
  }, skip: _haveDll ? false : _skip);

  test('render returns BGRA pixels of the requested size with the drawn content', () async {
    final bytes = _page();
    final px = await PdfiumWorker.instance.render('k1', bytes, 0, 200, 100);
    expect(px.length, 200 * 100 * 4);
    int at(int x, int y) => px[(y * 200 + x) * 4]; // blue channel
    expect(at(5, 5), 255, reason: 'page background is white');
    // block spans x 20..120, y (display) 30..80
    expect(at(60, 55), 0, reason: 'inside the black block');
    expect(at(150, 55), 255);
    // second call reuses the warm document (no bytes needed) and other pages work
    final p2 = await PdfiumWorker.instance.render('k1', bytes, 1, 100, 50);
    expect(p2.length, 100 * 50 * 4);
    expect(p2.every((b) => b == 255), isTrue, reason: 'page 2 is blank');
    await PdfiumWorker.instance.release('k1');
  }, skip: _haveDll ? false : _skip);

  test('evicted documents are transparently reloaded', () async {
    final bytes = _page();
    for (var i = 0; i < 9; i++) {
      await PdfiumWorker.instance.render('evict$i', bytes, 0, 20, 10);
    }
    // evict0 was pushed out of the 6-document cache; this must still work
    final px = await PdfiumWorker.instance.render('evict0', bytes, 0, 40, 20);
    expect(px.length, 40 * 20 * 4);
  }, skip: _haveDll ? false : _skip);

  test('baker work goes through the worker too', () async {
    final out = await analyzePagesAsync(_page(), [0, 1]);
    expect(out.map((p) => p.index), [0, 1]);
    expect(out.first.width, 200);
  }, skip: _haveDll ? false : _skip);
}
