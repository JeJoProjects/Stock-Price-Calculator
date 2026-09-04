/// Polls the Dart backend's /screener/top endpoint. The backend does the
/// actual Finnhub polling and filtering (see backend/lib/screener_service.dart)
/// — this client just fetches the already-computed cached result, so many
/// app instances can share one backend without multiplying API calls.
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'screener_models.dart';

class ScreenerClient {
  final String baseUrl;
  // Which backend screener this instance polls - /screener/finviz,
  // /screener/yahoo, or /screener/combined. Lets ScreenerHub reuse this one
  // class for all three tabs instead of three near-duplicate classes.
  final String endpointPath;
  Duration pollInterval;
  final http.Client _http;
  Timer? _timer;
  final _controller = StreamController<ScreenerSnapshot>.broadcast();

  ScreenerClient({
    this.baseUrl = 'http://localhost:8090',
    this.endpointPath = '/screener/finviz',
    this.pollInterval = const Duration(seconds: 30),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  Stream<ScreenerSnapshot> get snapshots => _controller.stream;

  void start() {
    _fetchOnce();
    _timer = Timer.periodic(pollInterval, (_) => _fetchOnce());
  }

  void stop() {
    _timer?.cancel();
  }

  /// Applies a new refresh cadence (from Preferences > Display) without
  /// tearing down and recreating the client - this only changes how often
  /// the app re-fetches the backend's already-cached result, not how often
  /// the backend itself polls Finviz/Yahoo.
  void setPollInterval(Duration interval) {
    if (interval == pollInterval) return;
    pollInterval = interval;
    if (_timer != null) {
      _timer!.cancel();
      _timer = Timer.periodic(pollInterval, (_) => _fetchOnce());
    }
  }

  /// Fetches immediately (for the panel's manual refresh button) and resets
  /// the periodic timer so the next scheduled fetch - and the UI's countdown
  /// to it - starts counting from now rather than from the old cadence.
  void refreshNow() {
    _fetchOnce();
    if (_timer != null) {
      _timer!.cancel();
      _timer = Timer.periodic(pollInterval, (_) => _fetchOnce());
    }
  }

  Future<void> _fetchOnce() async {
    try {
      final res = await _http.get(Uri.parse('$baseUrl$endpointPath'));
      if (res.statusCode != 200) {
        _controller.add(ScreenerSnapshot(error: 'Backend returned ${res.statusCode}.'));
        return;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      _controller.add(ScreenerSnapshot.fromJson(json));
    } catch (e) {
      _controller.add(ScreenerSnapshot(error: 'Could not reach backend: $e'));
    }
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
    _http.close();
  }
}
