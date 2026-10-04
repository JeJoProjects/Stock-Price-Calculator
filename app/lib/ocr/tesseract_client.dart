import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'image_recognizer.dart';
import 'ocr_models.dart';

/// Runs images through the Tesseract OCR engine as a subprocess - no
/// Python, no HTTP sidecar, works as long as tesseract.exe is reachable.
/// This is the default/fallback recognizer: lower accuracy than PaddleOCR
/// on stylized or complex layouts, but has zero setup beyond installing
/// Tesseract, so the OCR tab has a genuinely working engine even before
/// the optional PaddleOCR sidecar (see ocr_sidecar_client.dart) is built.
class TesseractClient implements ImageRecognizer {
  final String exePath;

  TesseractClient(this.exePath);

  /// Looks for tesseract.exe in order: bundled next to this app's own exe
  /// (future redistribution path, mirrors backend_launcher.dart), then
  /// common install locations used by the official Windows installer and
  /// package managers (winget/choco default to Program Files). Returns
  /// null if none exist - callers should treat that as "engine
  /// unavailable", same as an unreachable sidecar.
  static Future<TesseractClient?> detect() async {
    if (!Platform.isWindows) return null;

    final candidates = <String?>[
      _bundledPath(),
      r'C:\Program Files\Tesseract-OCR\tesseract.exe',
      r'C:\Program Files (x86)\Tesseract-OCR\tesseract.exe',
    ];

    for (final path in candidates) {
      if (path != null && await File(path).exists()) {
        return TesseractClient(path);
      }
    }

    // Last resort: whatever `tesseract` resolves to on PATH.
    try {
      final result = await Process.run('where', ['tesseract']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first.trim();
        if (path.isNotEmpty) return TesseractClient(path);
      }
    } catch (_) {
      // `where` itself missing/failing just means PATH lookup isn't
      // available - fall through to "not found".
    }

    return null;
  }

  static String? _bundledPath() {
    final appDir = File(Platform.resolvedExecutable).parent;
    return '${appDir.path}${Platform.pathSeparator}tesseract'
        '${Platform.pathSeparator}tesseract.exe';
  }

  @override
  Future<String> recognize(Uint8List imageBytes) async {
    final tempDir = await Directory.systemTemp.createTemp('stockcalc_ocr_');
    final inputFile = File('${tempDir.path}${Platform.pathSeparator}input.png');
    final outputBase = '${tempDir.path}${Platform.pathSeparator}output';

    try {
      await inputFile.writeAsBytes(imageBytes);

      final result = await Process.run(exePath, [inputFile.path, outputBase, '-l', 'eng'])
          .timeout(const Duration(seconds: 30));

      if (result.exitCode != 0) {
        throw OcrException(
          OcrErrorKind.extractionFailed,
          'Tesseract failed: ${(result.stderr as String).trim()}',
        );
      }

      final outputFile = File('$outputBase.txt');
      if (!await outputFile.exists()) {
        throw const OcrException(
            OcrErrorKind.extractionFailed, 'Tesseract did not produce any output.');
      }
      return await outputFile.readAsString();
    } on TimeoutException {
      throw const OcrException(OcrErrorKind.timeout, 'OCR took too long and was cancelled.');
    } finally {
      await tempDir.delete(recursive: true).catchError((_) => tempDir);
    }
  }
}
