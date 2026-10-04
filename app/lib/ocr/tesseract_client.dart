import 'dart:async';
import 'dart:convert';
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

  /// Folder holding *.traineddata. When null, Tesseract's own default is used.
  final String? tessdataDir;

  /// Languages to request, e.g. `eng+deu`.
  final String languages;

  TesseractClient(this.exePath, {this.tessdataDir, this.languages = 'eng'});

  /// Languages we want when available, in priority order. German goes first:
  /// Tesseract's combined models favour the first language, and `eng+deu`
  /// measurably dropped umlauts ("für" -> "fur") that `deu+eng` kept.
  /// Documents here are typically German and English; add codes (e.g. `mal`) by dropping the
  /// matching .traineddata into the bundled tessdata folder and listing it.
  static const preferredLanguages = ['deu', 'eng'];

  /// Picks `deu+eng`-style language string from the installed traineddata
  /// names, falling back to `eng` so a bare install still works.
  static String pickLanguages(Iterable<String> available) {
    final have = available.toSet();
    final chosen = preferredLanguages.where(have.contains).toList();
    return chosen.isEmpty ? 'eng' : chosen.join('+');
  }

  /// Builds a client for [exePath], using the bundled `tessdata` folder next
  /// to the app exe when it has English data, else Tesseract's default.
  static Future<TesseractClient> create(String exePath, {String? bundledTessdata}) async {
    if (bundledTessdata != null &&
        await File('$bundledTessdata${Platform.pathSeparator}eng.traineddata').exists()) {
      final names = <String>[
        await for (final e in Directory(bundledTessdata).list())
          if (e is File && e.path.toLowerCase().endsWith('.traineddata'))
            e.uri.pathSegments.last.replaceAll(RegExp(r'\.traineddata$', caseSensitive: false), ''),
      ];
      return TesseractClient(exePath,
          tessdataDir: bundledTessdata, languages: pickLanguages(names));
    }
    return TesseractClient(exePath);
  }

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
        return create(path, bundledTessdata: _bundledTessdata());
      }
    }

    // Last resort: whatever `tesseract` resolves to on PATH.
    try {
      final result = await Process.run('where', ['tesseract']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim().split('\n').first.trim();
        if (path.isNotEmpty) return await create(path, bundledTessdata: _bundledTessdata());
      }
    } catch (_) {
      // `where` itself missing/failing just means PATH lookup isn't
      // available - fall through to "not found".
    }

    return null;
  }

  static String _bundledTessdata() {
    final appDir = File(Platform.resolvedExecutable).parent;
    return '${appDir.path}${Platform.pathSeparator}tessdata';
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

      final result = await Process.run(exePath, [
        inputFile.path,
        outputBase,
        if (tessdataDir != null) ...['--tessdata-dir', tessdataDir!],
        '-l',
        languages,
      ]).timeout(const Duration(seconds: 60));

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
      return await outputFile.readAsString(encoding: utf8);
    } on TimeoutException {
      throw const OcrException(OcrErrorKind.timeout, 'OCR took too long and was cancelled.');
    } finally {
      await tempDir.delete(recursive: true).catchError((_) => tempDir);
    }
  }
}
