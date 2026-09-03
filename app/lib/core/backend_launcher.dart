/// Lets the app be genuinely double-click-and-go: instead of requiring a
/// separately started `dart run bin/server.dart` (or run_flutter.bat) every
/// time, the app checks whether the backend is already reachable and, if
/// not, launches the compiled backend exe itself - killing it again on
/// clean app close so it doesn't linger as an orphaned background process.
///
/// Windows desktop only. On any other platform (or if the backend exe isn't
/// found next to this one - e.g. a `flutter run` dev session that didn't go
/// through run_flutter.bat's build step), this quietly does nothing and the
/// existing "can't reach backend" empty states in the chart/screener panels
/// take over, same as before this existed.
library;

import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class BackendLauncher {
  final String baseUrl;
  final http.Client _http;
  Process? _owned;

  BackendLauncher({this.baseUrl = 'http://localhost:8090', http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// Starts the bundled backend exe if nothing is already answering at
  /// [baseUrl]. Safe to call even when a backend is already running
  /// (dev workflows, or a previous instance of this app) - it won't spawn
  /// a second one.
  Future<void> ensureRunning() async {
    if (!Platform.isWindows) return;
    if (await _isHealthy()) return;

    final exePath = _findBundledBackendExe();
    if (exePath == null) return;

    try {
      final process = await Process.start(exePath, [], workingDirectory: File(exePath).parent.path);
      _owned = process;
      // Drain stdout/stderr so the backend's own print()/stderr.writeln()
      // calls don't fill their pipe buffers and stall the child process.
      process.stdout.listen((_) {});
      process.stderr.listen((_) {});
    } catch (_) {
      // Backend exe missing a dependency, port already bound by something
      // else, etc. - the app's existing "can't reach backend" states cover
      // this the same as if auto-launch didn't exist at all.
    }
  }

  /// Kills the backend process only if this launcher is the one that
  /// started it - a backend that was already running before the app
  /// launched (dev workflow, another app instance) is left alone.
  void stopIfOwned() {
    _owned?.kill();
    _owned = null;
  }

  Future<bool> _isHealthy() async {
    try {
      final res = await _http.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// The build step (run_flutter.bat / setup_flutter.bat) compiles the
  /// backend and places it at backend/stockcalc_backend.exe next to this
  /// app's own exe, so it ships as part of the same Release folder.
  String? _findBundledBackendExe() {
    final appDir = File(Platform.resolvedExecutable).parent;
    final candidate = File('${appDir.path}${Platform.pathSeparator}backend${Platform.pathSeparator}stockcalc_backend.exe');
    return candidate.existsSync() ? candidate.path : null;
  }
}
