/// Polls Yahoo Finance's day-gainers screener on an interval and caches the
/// result - the exact same single-poller-many-clients shape as
/// finviz_screener_service.dart, just pointed at a different source.
library;

import 'dart:async';
import 'yahoo_client.dart';
import 'screener_row.dart';

class YahooScreenerService {
  final YahooClient client;
  final Duration pollInterval;
  final int limit;
  final void Function(List<ScreenerRow> rows, DateTime updatedAt, String? error)? onUpdate;

  List<ScreenerRow> _latest = [];
  DateTime? _lastUpdated;
  String? _lastError;
  bool _polling = false;
  Timer? _timer;

  YahooScreenerService({
    required this.client,
    this.pollInterval = const Duration(seconds: 30),
    this.limit = 25, // fetchTopGainers already caps at 25 (count=25)
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
      final rows = await client.fetchTopGainers();
      _latest = rows
          .take(limit)
          .map((r) => ScreenerRow(
                symbol: r.symbol,
                name: r.company,
                exchange: r.exchange,
                marketCap: r.marketCap,
                price: r.price,
                changePercent: r.changePercent,
                volume: r.volume,
                source: 'yahoo',
              ))
          .toList();
      _lastUpdated = DateTime.now();
      _lastError = null;
    } catch (e) {
      _lastError = 'Yahoo poll failed: $e';
    } finally {
      _polling = false;
      onUpdate?.call(_latest, _lastUpdated ?? DateTime.now(), _lastError);
    }
  }
}
