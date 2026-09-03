/// Polls Finviz's screener page on an interval and caches the result, so
/// many app instances can share one poller without multiplying Finviz
/// requests - same one-poller-many-clients shape as the old Finnhub-based
/// screener.
///
/// Unlike the Finnhub version this replaced, there's no isolate here: one
/// page fetch per cycle is a single lightweight HTTP call, not a loop of
/// dozens of rate-limited requests, so it doesn't need its own isolate to
/// avoid blocking the HTTP server.
library;

import 'dart:async';
import 'finviz_client.dart';
import 'screener_row.dart';

class FinvizScreenerService {
  final FinvizClient client;
  final Duration pollInterval;
  final int limit;
  final void Function(List<ScreenerRow> rows, DateTime updatedAt, String? error)? onUpdate;

  List<ScreenerRow> _latest = [];
  DateTime? _lastUpdated;
  String? _lastError;
  bool _polling = false;
  Timer? _timer;

  FinvizScreenerService({
    required this.client,
    this.pollInterval = const Duration(seconds: 30),
    this.limit = 20, // fetchUnusualVolumeMovers only pulls page 1 (top 20)
    this.onUpdate,
  });

  List<ScreenerRow> get latest => _latest;
  DateTime? get lastUpdated => _lastUpdated;
  String? get lastError => _lastError;

  void start() {
    _pollOnce();
    _timer = Timer.periodic(pollInterval, (_) => _pollOnce());
  }

  void stop() => _timer?.cancel();

  Future<void> _pollOnce() async {
    if (_polling) return;
    _polling = true;
    try {
      final rows = await client.fetchUnusualVolumeMovers();
      _latest = rows
          .take(limit)
          .map((r) => ScreenerRow(
                symbol: r.symbol,
                name: r.company,
                sector: r.sector,
                marketCap: r.marketCap,
                price: r.price,
                changePercent: r.changePercent,
                volume: r.volume,
              ))
          .toList();
      _lastUpdated = DateTime.now();
      _lastError = null;
    } catch (e) {
      _lastError = 'Finviz poll failed: $e';
    } finally {
      _polling = false;
      onUpdate?.call(_latest, _lastUpdated ?? DateTime.now(), _lastError);
    }
  }
}
