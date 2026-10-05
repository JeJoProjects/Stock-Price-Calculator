import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stockcalc/ocr/image_recognizer.dart';
import 'package:stockcalc/ocr/image_variants.dart';
import 'package:stockcalc/ocr/number_consensus.dart';
import 'package:stockcalc/ocr/ocr_sidecar_client.dart';
import 'package:stockcalc/ocr/tesseract_client.dart';
import 'package:image/image.dart' as img;

const _exe = r'C:\Program Files\Tesseract-OCR\tesseract.exe';
final _sep = Platform.pathSeparator;
final _bundledTessdata =
    '${Directory.current.path}${_sep}build${_sep}windows${_sep}x64${_sep}runner${_sep}Release${_sep}tessdata';

/// Every amount in the synthetic table. Mirrors the kinds of figures in
/// German insurance statements: thousands dots, decimal commas, zeros,
/// 2-digit cents, dates.
const _amounts = [
  '1.277,52', '127,75', '1.405,27', '0,00', '2.412,86', '154,81', '4,75', '37,72',
  '1.282,17', '14.282,17', '269,15', '722,30', '982,40', '1.249,60', '1.640,70', '216.984',
  '295.067', '375.325', '492.825', '30.04.2049', '597,80', '7,77', '2.460,48', '34,82',
];

/// Renders the amounts as a 3-column table, scan-like (Arial, ~200 dpi page),
/// via System.Drawing - Windows only, like the rest of this app's OCR stack.
Future<File?> _renderTable(Directory dir) async {
  final out = File('${dir.path}${_sep}table.png');
  final rows = <String>[];
  for (var i = 0; i < _amounts.length; i++) {
    final col = i % 3, row = i ~/ 3;
    rows.add('\$g.DrawString("${_amounts[i]}", \$f, [System.Drawing.Brushes]::Black, ${150 + col * 480}, ${90 + row * 70})');
  }
  final script = '''
Add-Type -AssemblyName System.Drawing
\$bmp = New-Object System.Drawing.Bitmap 1606, 800
\$g = [System.Drawing.Graphics]::FromImage(\$bmp)
\$g.Clear([System.Drawing.Color]::White)
\$g.TextRenderingHint = 'AntiAliasGridFit'
\$f = New-Object System.Drawing.Font 'Arial', 20
${rows.join('\n')}
\$bmp.Save('${out.path}', [System.Drawing.Imaging.ImageFormat]::Png)
''';
  final r = await Process.run('powershell', ['-NoProfile', '-Command', script]);
  return r.exitCode == 0 && out.existsSync() ? out : null;
}

class _FakeVerifier implements BoxRecognizer {
  final List<OcrBox> boxes;
  _FakeVerifier(this.boxes);
  @override
  Future<List<OcrBox>> recognizeBoxes(Uint8List imageBytes) async => boxes;
}

void main() {
  group('image variants', () {
    test('bilinear resize keeps size, flat areas flat and gradients monotonic', () {
      final flat = Uint8List.fromList(List.filled(10 * 10, 200));
      final up = resizeGrayBilinear(flat, 10, 10, 1.3);
      expect((up.width, up.height), (13, 13));
      expect(up.data.every((v) => v == 200), isTrue);

      final grad = Uint8List.fromList([for (var y = 0; y < 4; y++) for (var x = 0; x < 20; x++) x * 10]);
      final down = resizeGrayBilinear(grad, 20, 4, 0.9);
      expect((down.width, down.height), (18, 4));
      for (var x = 1; x < down.width; x++) {
        expect(down.data[x], greaterThanOrEqualTo(down.data[x - 1]));
      }
    });

    test('makeScaledVariants decodes an image and returns PGM copies at each scale', () async {
      final image = img.Image(width: 100, height: 60, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(10, 120, 250));
      final bytes = Uint8List.fromList(img.encodePng(image));

      final v = await makeScaledVariants(bytes, [0.9, 1.3]);

      expect(v, isNotNull);
      expect(v!.width, 100);
      expect(v.scaled.map((s) => s.scale), [0.9, 1.3]);
      expect(ascii.decode(v.scaled[1].pgm.sublist(0, 13)), startsWith('P5\n130 78\n255'));
    });

    test('undecodable bytes give null, not an exception', () async {
      expect(await makeScaledVariants(Uint8List.fromList([1, 2, 3]), [1.3]), isNull);
    });
  });

  group('tesseract tsv', () {
    test('parseTsv keeps only word rows with boxes', () {
      const tsv = 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n'
          '4\t1\t1\t1\t1\t0\t10\t20\t300\t30\t-1\t\n'
          '5\t1\t1\t1\t1\t1\t10\t20\t100\t30\t96.5\tBetrag\n'
          '5\t1\t1\t1\t1\t2\t120\t20\t90\t30\t91.0\t1.277,52\n'
          '5\t1\t1\t1\t1\t3\t220\t20\t10\t30\t12.0\t \n';
      final words = TesseractClient.parseTsv(tsv);
      expect(words.map((w) => w.text), ['Betrag', '1.277,52']);
      expect((words[1].left, words[1].top, words[1].width, words[1].height), (120, 20, 90, 30));
    });
  });

  group('sidecar boxes', () {
    test('recognizeBoxes maps items to boxes', () async {
      final mock = MockClient((_) async => http.Response(
          jsonEncode({
            'text': 'x',
            'items': [
              {'t': '1.277,52', 'c': 0.99, 'x': 100.0, 'x2': 180.0, 'y': 50.0, 'h': 20.0},
              {'bad': true},
            ],
          }),
          200));
      final boxes = await OcrSidecarClient(httpClient: mock).recognizeBoxes(Uint8List(1));
      expect(boxes, hasLength(1));
      expect(boxes.single.text, '1.277,52');
      expect((boxes.single.left, boxes.single.width, boxes.single.top, boxes.single.height),
          (100.0, 80.0, 50.0, 20.0));
    });

    test('an old sidecar without items yields no boxes (graceful)', () async {
      final mock = MockClient((_) async => http.Response(jsonEncode({'text': 'x'}), 200));
      expect(await OcrSidecarClient(httpClient: mock).recognizeBoxes(Uint8List(1)), isEmpty);
    });
  });

  group('real Tesseract on a synthetic amount table', () {
    final haveEngine = Platform.isWindows && File(_exe).existsSync();
    final haveGerman = File('$_bundledTessdata${_sep}deu.traineddata').existsSync();
    final skip = !haveEngine || !haveGerman
        ? 'needs Tesseract + bundled German data (run setup_flutter.bat first)'
        : false;

    Future<(TesseractClient, Uint8List)> setup() async {
      final dir = Directory.systemTemp.createTempSync('ocr_table');
      addTearDown(() => dir.deleteSync(recursive: true));
      final image = await _renderTable(dir);
      expect(image, isNotNull, reason: 'could not render the test table');
      final client = await TesseractClient.create(_exe, bundledTessdata: _bundledTessdata);
      return (client, await image!.readAsBytes());
    }

    void expectAllAmounts(String text) {
      final found = RegExp(r'\d[\d.,]*\d|\d').allMatches(text).map((m) => m.group(0)).toList();
      for (final a in _amounts) {
        expect(found, contains(a), reason: 'missing or misread "$a" in:\n$text');
      }
      expect(found.length, _amounts.length, reason: 'unexpected extra numbers in:\n$text');
    }

    test('multi-pass pipeline reads every amount exactly', () async {
      final (client, bytes) = await setup();
      expectAllAmounts(await client.recognize(bytes));
    }, skip: skip);

    test('a wrong verifier cannot corrupt numbers the Tesseract passes agree on', () async {
      final (client, bytes) = await setup();
      // Same positions as the table's first row, but different digits.
      final lies = [OcrBox('9.999,99', 150, 90, 150, 30), OcrBox('888,88', 630, 90, 120, 30)];
      final text = await client.withVerifier(_FakeVerifier(lies)).recognize(bytes);
      expectAllAmounts(text);
    }, skip: skip);
  });
}
