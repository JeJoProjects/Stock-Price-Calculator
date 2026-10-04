import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/ocr/image_recognizer.dart';
import 'package:stockcalc/ocr/ocr_batch.dart';
import 'package:stockcalc/ocr/ocr_service.dart';

class _FakeRecognizer implements ImageRecognizer {
  final Map<int, String> byLength;
  _FakeRecognizer(this.byLength);

  @override
  int get preferredConcurrency => 1;

  @override
  Future<String> recognize(Uint8List imageBytes) async {
    final text = byLength[imageBytes.length];
    if (text == null) throw StateError('boom');
    return text;
  }
}

void main() {
  ocrBatchRetryTests();
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('ocr_batch_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  File img(String relative, int size) {
    final f = File('${tempDir.path}/$relative')..createSync(recursive: true);
    f.writeAsBytesSync(List.filled(size, 1));
    return f;
  }

  test('labelFromFileName builds CamelCase and keeps existing CamelCase', () {
    expect(labelFromFileName('GermanA1Certificate2021.png'), 'GermanA1Certificate2021');
    expect(labelFromFileName('german a1 certificate-2021.jpg'), 'GermanA1Certificate2021');
    expect(labelFromFileName('...png'), 'Untitled');
  });

  test('labelFromFileName keeps umlauts and dotted numbers (real German file names)', () {
    expect(labelFromFileName('1.1 - 01.2022 - Jährliche Mitteilung zum Stand.jpg'),
        '1.1_01.2022JährlicheMitteilungZumStand');
    expect(labelFromFileName('2.6 - 06.2022 - Garantiewerte.jpg'), '2.6_06.2022Garantiewerte');
    expect(labelFromFileName('1.3 - 01.2022 - Wertmitteilung.jpg'), '1.3_01.2022Wertmitteilung');
  });

  test('every file name in a numbered series gets a distinct label', () {
    final names = [for (var i = 1; i <= 7; i++) '1.$i - 01.2022 - Wertmitteilung.jpg'];
    expect(names.map(labelFromFileName).toSet().length, names.length);
  });

  test('naturalCompare orders numbers numerically', () {
    final names = ['p10.png', 'p2.png', 'p1.png']..sort(naturalCompare);
    expect(names, ['p1.png', 'p2.png', 'p10.png']);
  });

  test('expandInputs walks folders recursively and counts unsupported files', () async {
    img('a/p2.png', 2);
    img('a/p10.png', 3);
    img('a/sub/p1.jpg', 4);
    File('${tempDir.path}/a/notes.txt').writeAsStringSync('x');

    final r = await expandInputs([tempDir.path]);

    expect(r.skipped, 1);
    expect(r.files.map((p) => p.split(RegExp(r'[\\/]')).last), ['p2.png', 'p10.png', 'p1.jpg']);
  });

  test('batch runs every file in order, isolates failures, and builds one markdown', () async {
    final a = img('a.png', 5);
    final b = img('b.png', 6); // not in fake map -> engine throws
    final c = img('c.png', 7);
    final batch = OcrBatchController(OcrService(
      recognizer: _FakeRecognizer({5: 'alpha text', 7: 'gamma ``` text'}),
    ));

    await batch.addPaths([a.path, b.path, c.path, a.path]);

    expect(batch.items.map((i) => i.status.name), ['done', 'error', 'done']);
    expect(batch.notice, contains('already in the list'));

    final md = buildOcrMarkdown(
      title: 'Test Run',
      items: batch.items,
      generatedAt: DateTime(2026, 10, 5, 9, 30),
    );
    expect(md, startsWith('# Test Run'));
    expect(md, contains('3 files - generated 2026-10-05 09:30'));
    expect(md, contains('### Document 1 - `A`'));
    expect(md, contains('alpha text'));
    expect(md, contains('### Document 2 - `B`'));
    expect(md, contains('[OCR failed:'));
    // Text containing a ``` run gets a longer fence so the block stays intact.
    expect(md, contains('````\ngamma ``` text\n````'));
    batch.dispose();
  });

  test('duplicate labels get a numeric suffix', () {
    final one = OcrBatchItem(path: 'x/Scan.png', name: 'Scan.png')..status = OcrItemStatus.done;
    final two = OcrBatchItem(path: 'y/Scan.png', name: 'Scan.png')..status = OcrItemStatus.done;
    final md = buildOcrMarkdown(title: 't', items: [one, two]);
    expect(md, contains('`Scan`'));
    expect(md, contains('`Scan (2)`'));
  });
}

class _SlowRecognizer implements ImageRecognizer {
  int running = 0, maxRunning = 0;
  @override
  int get preferredConcurrency => 3;

  @override
  Future<String> recognize(Uint8List imageBytes) async {
    maxRunning = ++running > maxRunning ? running : maxRunning;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    running--;
    return 'text${imageBytes.length}';
  }
}

void ocrBatchRetryTests() {
  test('files are processed in parallel up to the engine concurrency, results stay in order',
      () async {
    final dir = Directory.systemTemp.createTempSync('ocr_parallel_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final paths = [
      for (var i = 1; i <= 9; i++)
        (File('${dir.path}/f$i.png')..writeAsBytesSync(List.filled(i, 1))).path,
    ];
    final engine = _SlowRecognizer();
    final batch = OcrBatchController(OcrService(recognizer: engine));

    await batch.addPaths(paths);

    expect(engine.maxRunning, 3);
    expect(batch.items.every((i) => i.status == OcrItemStatus.done), isTrue);
    expect(batch.items.map((i) => i.text).toList(), [for (var i = 1; i <= 9; i++) 'text$i']);
    batch.dispose();
  });

  test('files that failed for lack of an engine are retried when one arrives', () async {
    final dir = Directory.systemTemp.createTempSync('ocr_retry_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/a.png')..writeAsBytesSync(List.filled(5, 1));

    final batch = OcrBatchController(OcrService()); // no engine yet
    await batch.addPaths([f.path]);
    expect(batch.items.single.status, OcrItemStatus.error);
    expect(batch.items.single.error, contains('Tesseract'));

    batch.service = OcrService(recognizer: _FakeRecognizer({5: 'now works'}));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(batch.items.single.status, OcrItemStatus.done);
    expect(batch.items.single.text, 'now works');
    batch.dispose();
  });
}
