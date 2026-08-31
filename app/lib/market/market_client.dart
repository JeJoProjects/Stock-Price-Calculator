/// Ported from src/market/marketDataService.cpp, but as a simple async
/// client against the Dart backend instead of a manual worker-thread +
/// condition-variable cache (Dart's async/await makes that unnecessary).
///
/// Unlike the old app, this cache has a real TTL (the old one cached a
/// symbol+timeframe forever until restart) - see migration plan's Market
/// data section.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'market_types.dart';

class _CacheEntry {
  final MarketSnapshot snapshot;
  final DateTime fetchedAt;
  _CacheEntry(this.snapshot, this.fetchedAt);
}

class MarketDataService {
  final String baseUrl;
  final Duration ttl;
  final http.Client _http;
  final Map<String, _CacheEntry> _cache = {};

  MarketDataService({
    this.baseUrl = 'http://localhost:8090',
    this.ttl = const Duration(seconds: 30),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  String _cacheKey(String symbol, Timeframe timeframe) => '$symbol|${timeframe.name}';

  Future<MarketSnapshot> fetchSnapshot(String symbol, Timeframe timeframe) async {
    final key = _cacheKey(symbol, timeframe);
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < ttl) {
      return cached.snapshot;
    }

    try {
      final results = await Future.wait([
        _http.get(Uri.parse('$baseUrl/quote/$symbol')),
        _http.get(Uri.parse('$baseUrl/profile/$symbol')),
        _http.get(Uri.parse('$baseUrl/candles/$symbol?timeframe=${timeframe.label}')),
      ]);

      final quoteRes = results[0];
      final profileRes = results[1];
      final candlesRes = results[2];

      String? error;
      Quote? quote;
      CompanyProfile? profile;
      var candles = <Candle>[];

      if (quoteRes.statusCode == 200) {
        quote = Quote.fromJson(jsonDecode(quoteRes.body) as Map<String, dynamic>);
      } else {
        error = (jsonDecode(quoteRes.body) as Map<String, dynamic>)['error'] as String? ??
            'Quote request failed.';
      }
      if (profileRes.statusCode == 200) {
        profile = CompanyProfile.fromJson(jsonDecode(profileRes.body) as Map<String, dynamic>);
      }
      if (candlesRes.statusCode == 200) {
        final body = jsonDecode(candlesRes.body) as Map<String, dynamic>;
        candles = (body['candles'] as List).map((c) => Candle.fromJson(c)).toList();
      } else {
        error ??= (jsonDecode(candlesRes.body) as Map<String, dynamic>)['error'] as String? ??
            'No chart data available.';
      }

      final snapshot = MarketSnapshot(
        symbol: symbol,
        timeframe: timeframe,
        quote: quote,
        profile: profile,
        candles: candles,
        error: error,
      );
      _cache[key] = _CacheEntry(snapshot, DateTime.now());
      return snapshot;
    } catch (e) {
      return MarketSnapshot(
        symbol: symbol,
        timeframe: timeframe,
        error: 'Could not reach backend: $e',
      );
    }
  }

  void close() => _http.close();
}
