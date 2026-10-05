// Local dev tool: OCR every image in a folder with the app's real pipeline
// and write one .txt per image, for comparing against another OCR's output.
//
//   dart run tool/ocr_eval.dart --in <folder> --out <folder> [--sidecar]
//       [--no-verify] [--workers 6]
//
// --sidecar   also use the PaddleOCR sidecar (--sidecar-url, default :8091) as a
//             second opinion on numbers.
// --no-verify plain single-pass Tesseract (the old behaviour).
import 'dart:async';
import 'dart:io';
import 'package:stockcalc/ocr/ocr_sidecar_client.dart';
import 'package:stockcalc/ocr/tesseract_client.dart';

Future<void> main(List<String> args) async {
  String? arg(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final inDir = Directory(arg('--in') ?? '.');
  final outDir = Directory(arg('--out') ?? 'ocr_eval_out')..createSync(recursive: true);
  final workers = int.tryParse(arg('--workers') ?? '') ?? 6;
  final exe = r'C:\Program Files\Tesseract-OCR\tesseract.exe';
  final tessdata = arg('--tessdata') ??
      '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}windows'
          '${Platform.pathSeparator}x64${Platform.pathSeparator}runner${Platform.pathSeparator}Release'
          '${Platform.pathSeparator}tessdata';

  var client = await TesseractClient.create(exe, bundledTessdata: tessdata);
  if (args.contains('--no-verify')) {
    client = TesseractClient(exe,
        tessdataDir: client.tessdataDir, languages: client.languages, verifyScales: const []);
  }
  if (args.contains('--sidecar')) {
    client = client.withVerifier(OcrSidecarClient(baseUrl: arg('--sidecar-url') ?? 'http://127.0.0.1:8091'));
  }
  final fixLog = <String>[];
  stdout.writeln('languages=${client.languages} scales=${client.verifyScales} '
      'sidecar=${client.verifier != null}');

  final files = inDir
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'\.(png|jpe?g)$', caseSensitive: false).hasMatch(f.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final sw = Stopwatch()..start();
  var next = 0;
  Future<void> worker() async {
    while (next < files.length) {
      final f = files[next++];
      final t = Stopwatch()..start();
      final name = f.uri.pathSegments.last;
      final c = client.withVerifier(client.verifier);
      c.onConsensus = (r) {
        for (final fix in r.fixes) {
          fixLog.add('${name.substring(0, 3)}  $fix');
        }
      };
      if (args.contains('--explain')) {
        c.onVotes = (ds) {
          for (final d in ds) {
            if (d.votes.length > 1) {
              stdout.writeln('VOTE ${name.substring(0, 3)} ${d.token.text} @(${d.token.cx.round()},${d.token.cy.round()}) '
                  '${d.votes} -> ${d.to}');
            }
          }
        };
      }
      final text = await c.recognize(await f.readAsBytes());
      File('${outDir.path}${Platform.pathSeparator}${name.substring(0, 3)}.txt')
          .writeAsStringSync(text);
      stdout.writeln('${name.substring(0, 3)}  ${t.elapsedMilliseconds} ms');
    }
  }

  await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  fixLog.sort();
  for (final l in fixLog) {
    stdout.writeln('FIX $l');
  }
  stdout.writeln('total ${sw.elapsedMilliseconds} ms for ${files.length} files');
  exit(0);
}
