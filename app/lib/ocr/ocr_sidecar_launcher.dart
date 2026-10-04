/// Self-launches the bundled PaddleOCR sidecar exe, mirroring
/// core/backend_launcher.dart's pattern exactly. The one difference: the
/// sidecar's model load is slow, so health has three states instead of
/// two - unreachable, warming up (process is up, models still loading),
/// and ready - rather than just healthy/unhealthy.
///
/// Windows desktop only. If the sidecar exe isn't bundled (e.g. the
/// optional Python/PyInstaller setup step was skipped), this quietly does
/// nothing and the OCR tab shows its "engine unavailable" state, same as
/// backend_launcher.dart does for the Dart backend.
library;

import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

enum OcrEngineStatus { unreachable, warmingUp, ready }

class OcrSidecarLauncher {
  final String baseUrl;
  final http.Client _http;
  Process? _owned;

  OcrSidecarLauncher({this.baseUrl = 'http://127.0.0.1:8091', http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// Starts the bundled sidecar exe if nothing is already answering at
  /// [baseUrl]. Safe to call repeatedly - it won't spawn a second one.
  Future<void> ensureRunning() async {
    if (!Platform.isWindows) return;
    if (await status() != OcrEngineStatus.unreachable) return;

    final exePath = _findBundledSidecarExe();
    if (exePath == null) return;

    try {
      final process = await Process.start(exePath, [], workingDirectory: File(exePath).parent.path);
      _owned = process;
      process.stdout.listen((_) {});
      process.stderr.listen((_) {});
    } catch (_) {
      // Sidecar exe missing a dependency, port already bound, etc. - the
      // OCR tab's "engine unavailable" state covers this the same as if
      // auto-launch didn't exist at all.
    }
  }

  /// Kills the sidecar process only if this launcher is the one that
  /// started it.
  void stopIfOwned() {
    _owned?.kill();
    _owned = null;
  }

  Future<OcrEngineStatus> status() async {
    try {
      final res = await _http.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) return OcrEngineStatus.ready;
      if (res.statusCode == 503) return OcrEngineStatus.warmingUp;
      return OcrEngineStatus.unreachable;
    } catch (_) {
      return OcrEngineStatus.unreachable;
    }
  }

  /// The build step compiles the sidecar and places it at
  /// ocr_sidecar/stockcalc_ocr.exe next to this app's own exe, same layout
  /// as the Dart backend.
  String? _findBundledSidecarExe() {
    final appDir = File(Platform.resolvedExecutable).parent;
    final candidate = File(
        '${appDir.path}${Platform.pathSeparator}ocr_sidecar${Platform.pathSeparator}stockcalc_ocr.exe');
    return candidate.existsSync() ? candidate.path : null;
  }
}
