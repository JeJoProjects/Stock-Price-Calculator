/// Disk-backed cache for candle data, keyed by symbol+timeframe.
///
/// Why this exists: BackendLauncher spawns a fresh backend process every
/// time the app starts and kills it when the app closes (see
/// app/lib/core/backend_launcher.dart) - so an in-memory-only cache would
/// be wiped on every single app restart. Since Alpha Vantage's free tier
/// allows roughly 25 requests/day (see alpha_vantage_client.dart), that
/// would make the quota nearly useless for anyone who opens/closes the app
/// more than a couple of times a day. Persisting to a small JSON file next
/// to the backend exe survives restarts and makes the free tier actually
/// usable across a normal day.
library;

import 'dart:convert';
import 'dart:io';

import 'market_types.dart';

class CandleCache {
  final File _file;
  final Duration ttl;
  Map<String, dynamic> _data = {};
  bool _loaded = false;

  CandleCache({required String path, required this.ttl}) : _file = File(path);

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    if (await _file.exists()) {
      try {
        _data = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        _data = {};
      }
    }
  }

  String _key(String symbol, Timeframe timeframe) => '${symbol.toUpperCase()}|${timeframe.name}';

  Future<List<Candle>?> get(String symbol, Timeframe timeframe) async {
    await _ensureLoaded();
    final entry = _data[_key(symbol, timeframe)] as Map<String, dynamic>?;
    if (entry == null) return null;
    final fetchedAt = DateTime.tryParse(entry['fetchedAt'] as String? ?? '');
    if (fetchedAt == null || DateTime.now().difference(fetchedAt) > ttl) return null;
    final list = entry['candles'] as List;
    return list
        .map((c) => Candle(
              time: c['time'] as int,
              open: (c['open'] as num).toDouble(),
              high: (c['high'] as num).toDouble(),
              low: (c['low'] as num).toDouble(),
              close: (c['close'] as num).toDouble(),
              volume: (c['volume'] as num).toDouble(),
            ))
        .toList();
  }

  Future<void> set(String symbol, Timeframe timeframe, List<Candle> candles) async {
    await _ensureLoaded();
    _data[_key(symbol, timeframe)] = {
      'fetchedAt': DateTime.now().toIso8601String(),
      'candles': candles.map((c) => c.toJson()).toList(),
    };
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode(_data));
    } catch (_) {
      // Best-effort - a failed write just means the next restart re-fetches
      // instead of reading a stale/missing cache. Never worth crashing the
      // backend over.
    }
  }
}
