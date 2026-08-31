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
  final Duration pollInterval;
  final http.Client _http;
  Timer? _timer;
  final _controller = StreamController<ScreenerSnapshot>.broadcast();

  ScreenerClient({
    this.baseUrl = 'http://localhost:8090',
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

  Future<void> _fetchOnce() async {
    try {
      final res = await _http.get(Uri.parse('$baseUrl/screener/top'));
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
