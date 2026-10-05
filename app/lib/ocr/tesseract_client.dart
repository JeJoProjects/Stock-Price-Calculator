import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'image_recognizer.dart';
import 'image_variants.dart';
import 'number_consensus.dart';
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

  /// Second opinion on numbers (e.g. the PaddleOCR sidecar). Optional.
  final BoxRecognizer? verifier;

  /// Extra page scales read to cross-check numbers. Empty disables the
  /// multi-pass check (single fast pass, like plain Tesseract).
  final List<double> verifyScales;

  /// Diagnostics: called with every consensus result (fixes applied).
  void Function(ConsensusResult result)? onConsensus;
  void Function(List<({String? to, NumToken token, Map<String, double> votes})>)? onVotes;

  /// Vote weight of [verifier] relative to one extra Tesseract pass.
  static const verifierWeight = 2.5;

  TesseractClient(
    this.exePath, {
    this.tessdataDir,
    this.languages = 'eng',
    this.verifier,
    this.verifyScales = defaultVerifyScales,
  });

  /// Measured on real scans: 0.9x and 1.3x disagree with the 1.0x pass in
  /// different places, so together they out-vote its occasional digit slip.
  static const defaultVerifyScales = [0.9, 1.3];

  TesseractClient withVerifier(BoxRecognizer? v) => TesseractClient(exePath,
      tessdataDir: tessdataDir,
      languages: languages,
      verifier: v,
      verifyScales: verifyScales);

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

  /// One single-threaded Tesseract process per core beats one multi-threaded
  /// process at a time (its OpenMP threading scales poorly). Leave a core
  /// free for the UI, cap at 6 to bound memory.
  @override
  int get preferredConcurrency => (Platform.numberOfProcessors - 1).clamp(1, 6);

  @override
  Future<String> recognize(Uint8List imageBytes) async {
    final tempDir = await Directory.systemTemp.createTemp('stockcalc_ocr_');
    try {
      final primary = await _pass(tempDir, 'primary', imageBytes);
      if ((verifyScales.isEmpty && verifier == null) || !_hasSignificantNumbers(primary.words)) {
        return normalizeAmounts(primary.text);
      }

      final voters = <NumberVoter>[];
      var pageWidth = 0.0;

      // The sidecar call is network/CPU-bound elsewhere, so start it first.
      final verifierFuture = verifier?.recognizeBoxes(imageBytes).then<List<OcrBox>?>((b) => b,
          onError: (_) => null);

      if (verifyScales.isNotEmpty) {
        final variants = await makeScaledVariants(imageBytes, verifyScales);
        if (variants != null) {
          pageWidth = variants.width.toDouble();
          for (final v in variants.scaled) {
            try {
              final pass = await _pass(tempDir, 'x${v.scale}', v.pgm);
              voters.add(NumberVoter([for (final w in pass.words) w.scaled(1 / v.scale)], 1.0));
            } on Object {
              // A failed extra pass just means one fewer vote.
            }
          }
        }
      }

      final fromVerifier = await verifierFuture;
      if (fromVerifier != null && fromVerifier.isNotEmpty) {
        voters.add(NumberVoter(fromVerifier, verifierWeight));
      }
      if (pageWidth == 0) {
        pageWidth = primary.words.fold<double>(0, (m, w) => w.left + w.width > m ? w.left + w.width : m);
      }
      if ((voters.isEmpty && (fromVerifier == null || fromVerifier.isEmpty)) || pageWidth == 0) {
        return normalizeAmounts(primary.text);
      }

      final result = applyNumberConsensus(primary.text, primary.words, voters, pageWidth,
          recoverFrom: fromVerifier ?? const []);
      onConsensus?.call(result);
      onVotes?.call(decide(primary.words, voters, pageWidth));
      return result.text;
    } on TimeoutException {
      throw const OcrException(OcrErrorKind.timeout, 'OCR took too long and was cancelled.');
    } finally {
      await tempDir.delete(recursive: true).catchError((_) => tempDir);
    }
  }

  static bool _hasSignificantNumbers(List<OcrBox> words) => numericTokens(words)
      .any((t) => t.text.replaceAll(RegExp(r'\D'), '').length >= 2);

  /// Runs one Tesseract pass, returning the plain text and word boxes.
  Future<({String text, List<OcrBox> words})> _pass(
      Directory dir, String name, Uint8List bytes) async {
    final input = File('${dir.path}${Platform.pathSeparator}$name.img');
    final outBase = '${dir.path}${Platform.pathSeparator}$name';
    await input.writeAsBytes(bytes);

    final result = await Process.run(
      exePath,
      [
        input.path,
        outBase,
        if (tessdataDir != null) ...['--tessdata-dir', tessdataDir!],
        '-l',
        languages,
        '-c',
        'tessedit_create_txt=1',
        '-c',
        'tessedit_create_tsv=1',
      ],
      environment: const {'OMP_THREAD_LIMIT': '1'},
    ).timeout(const Duration(seconds: 90));

    if (result.exitCode != 0) {
      throw OcrException(
        OcrErrorKind.extractionFailed,
        'Tesseract failed: ${(result.stderr as String).trim()}',
      );
    }
    final txt = File('$outBase.txt');
    if (!await txt.exists()) {
      throw const OcrException(
          OcrErrorKind.extractionFailed, 'Tesseract did not produce any output.');
    }
    final tsv = File('$outBase.tsv');
    return (
      text: await txt.readAsString(encoding: utf8),
      words: await tsv.exists() ? parseTsv(await tsv.readAsString(encoding: utf8)) : <OcrBox>[],
    );
  }

  /// Parses Tesseract TSV output into word boxes (level-5 rows).
  static List<OcrBox> parseTsv(String tsv) {
    final words = <OcrBox>[];
    for (final line in const LineSplitter().convert(tsv)) {
      final c = line.split('	');
      if (c.length < 12 || c[0] != '5') continue;
      final text = c.sublist(11).join('	').trim();
      if (text.isEmpty) continue;
      final l = double.tryParse(c[6]), t = double.tryParse(c[7]);
      final w = double.tryParse(c[8]), h = double.tryParse(c[9]);
      if (l == null || t == null || w == null || h == null) continue;
      words.add(OcrBox(text, l, t, w, h));
    }
    return words;
  }
}
