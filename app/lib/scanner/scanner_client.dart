/// Live connection to the backend's scanner: a local WebSocket
/// (`ws://localhost:8090/live`) on which the backend pushes a full snapshot
/// several times a second while prices move. No polling, no manual refresh.
/// Reconnects with backoff, so starting before the backend is up (or the
/// backend restarting) just shows "connecting" until it is back - same
/// fail-soft rule as the rest of the app's local services.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'scanner_models.dart';

enum ScannerLink { connecting, connected, disconnected }

typedef ScannerSocketConnector = Future<WebSocket> Function(Uri url);

class ScannerClient {
  ScannerClient({Uri? url, ScannerSocketConnector? connect})
      : url = url ?? Uri.parse('ws://localhost:8090/live'),
        _connect = connect ?? ((u) => WebSocket.connect(u.toString()));

  final Uri url;
  final ScannerSocketConnector _connect;

  final _snapshots = StreamController<ScannerSnapshot>.broadcast();
  final _links = StreamController<ScannerLink>.broadcast();

  ScannerSnapshot? latest;
  ScannerLink link = ScannerLink.connecting;
  String? lastError;

  WebSocket? _ws;
  bool _running = false;
  int _attempt = 0;

  Stream<ScannerSnapshot> get snapshots => _snapshots.stream;
  Stream<ScannerLink> get links => _links.stream;

  void start() {
    if (_running) return;
    _running = true;
    _loop();
  }

  Future<void> _loop() async {
    while (_running) {
      _setLink(ScannerLink.connecting);
      try {
        final ws = await _connect(url).timeout(const Duration(seconds: 5));
        _ws = ws;
        _attempt = 0;
        lastError = null;
        _setLink(ScannerLink.connected);
        // The backend sends at least one frame every ~5s (heartbeat).
        await for (final m in ws.timeout(const Duration(seconds: 20), onTimeout: (sink) => sink.close())) {
          if (m is! String) continue;
          final Object? json;
          try {
            json = jsonDecode(m);
          } on FormatException {
            continue;
          }
          if (json is Map<String, dynamic> && json['type'] == 'snapshot') {
            final snap = ScannerSnapshot.fromJson(json);
            latest = snap;
            if (!_snapshots.isClosed) _snapshots.add(snap);
          }
        }
      } on Object catch (e) {
        lastError = '$e';
      }
      await _ws?.close();
      _ws = null;
      if (!_running) break;
      _setLink(ScannerLink.disconnected);
      const waits = [1, 1, 2, 3, 5];
      await Future<void>.delayed(Duration(seconds: waits[_attempt.clamp(0, waits.length - 1)]));
      _attempt++;
    }
  }

  void _setLink(ScannerLink l) {
    link = l;
    if (!_links.isClosed) _links.add(l);
  }

  Future<void> dispose() async {
    _running = false;
    await _ws?.close();
    await _snapshots.close();
    await _links.close();
  }
}
