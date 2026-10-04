import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/ocr/ocr_batch.dart';
import 'package:stockcalc/ocr/ocr_service.dart';
import 'package:stockcalc/ocr/tesseract_client.dart';

const _tesseractExe = r'C:\Program Files\Tesseract-OCR\tesseract.exe';
final _bundledTessdata = '${Directory.current.path}${Platform.pathSeparator}build'
    '${Platform.pathSeparator}windows${Platform.pathSeparator}x64${Platform.pathSeparator}runner'
    '${Platform.pathSeparator}Release${Platform.pathSeparator}tessdata';

/// Renders German text to a PNG with System.Drawing (Windows only).
Future<File?> _renderGermanImage(Directory dir) async {
  final out = File('${dir.path}${Platform.pathSeparator}1.3 - 01.2022 - Wertmitteilung.png');
  final script = '''
Add-Type -AssemblyName System.Drawing
\$bmp = New-Object System.Drawing.Bitmap 1400, 420
\$g = [System.Drawing.Graphics]::FromImage(\$bmp)
\$g.Clear([System.Drawing.Color]::White)
\$g.TextRenderingHint = 'AntiAliasGridFit'
\$f = New-Object System.Drawing.Font 'Arial', 40
\$g.DrawString("J\$([char]0xE4)hrliche Mitteilung f\$([char]0xFC)r Gr\$([char]0xF6)\$([char]0xDF)e", \$f, [System.Drawing.Brushes]::Black, 30, 40)
\$g.DrawString("Wertmitteilung Versicherungsnummer 123456", \$f, [System.Drawing.Brushes]::Black, 30, 160)
\$g.DrawString("Garantiewerte Stand 01.2022", \$f, [System.Drawing.Brushes]::Black, 30, 280)
\$bmp.Save('${out.path}', [System.Drawing.Imaging.ImageFormat]::Png)
''';
  final r = await Process.run('powershell', ['-NoProfile', '-Command', script]);
  return r.exitCode == 0 && out.existsSync() ? out : null;
}

void main() {
  test('pickLanguages prefers deu+eng and falls back to eng', () {
    expect(TesseractClient.pickLanguages(['osd', 'deu', 'eng']), 'deu+eng');
    expect(TesseractClient.pickLanguages(['eng', 'osd']), 'eng');
    expect(TesseractClient.pickLanguages(['fra']), 'eng');
  });

  final haveEngine = Platform.isWindows && File(_tesseractExe).existsSync();
  final haveGerman = File('$_bundledTessdata${Platform.pathSeparator}deu.traineddata').existsSync();

  test('end-to-end: real Tesseract reads a German image through the batch pipeline', () async {
    final dir = Directory.systemTemp.createTempSync('ocr_e2e');
    addTearDown(() => dir.deleteSync(recursive: true));
    final image = await _renderGermanImage(dir);
    expect(image, isNotNull, reason: 'could not render the test image');

    final client = await TesseractClient.create(_tesseractExe, bundledTessdata: _bundledTessdata);
    expect(client.languages, 'deu+eng');

    final batch = OcrBatchController(OcrService(recognizer: client));
    await batch.addPaths([dir.path]);

    final item = batch.items.single;
    expect(item.status, OcrItemStatus.done, reason: item.error);
    expect(item.text, contains('Wertmitteilung'));
    expect(item.text, contains('Jährliche'));
    expect(item.text, contains('Garantiewerte'));
    expect(item.text, contains('für Größe'));

    final md = batch.toMarkdown('E2E');
    expect(md, contains('### Document 1 - `1.3_01.2022Wertmitteilung`'));
    expect(md, contains('Wertmitteilung Versicherungsnummer'));
    batch.dispose();
  },
      skip: !haveEngine || !haveGerman
          ? 'needs Tesseract + the bundled German data (run setup_flutter.bat first)'
          : false);
}
