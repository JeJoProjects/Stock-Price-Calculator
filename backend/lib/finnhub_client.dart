/// Ported from src/market/finnhubClient.cpp, but using package:http + real
/// JSON decoding instead of raw WinHTTP + hand-rolled substring scanning
/// (the old client was Windows-only and had no real JSON parser).
///
/// KNOWN RISK (flagged in the migration plan): Finnhub's /stock/candle
/// endpoint has moved behind a paid plan on newer accounts. fetchCandles
/// will surface that as an error string rather than throwing, matching the
/// old app's "No chart data returned." behavior, so callers can degrade
/// gracefully.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'market_types.dart';

class FinnhubResult<T> {
  final T? value;
  final String? error;
  const FinnhubResult.ok(this.value) : error = null;
  const FinnhubResult.err(this.error) : value = null;
  bool get isOk => value != null;
}

class FinnhubClient {
  final String apiKey;
  final http.Client _http;

  FinnhubClient({required this.apiKey, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  bool get hasApiKey => apiKey.isNotEmpty;

  Uri _uri(String path, Map<String, String> query) => Uri.https(
        'finnhub.io',
        path,
        {...query, 'token': apiKey},
      );

  Future<FinnhubResult<Quote>> fetchQuote(String symbol) async {
    if (!hasApiKey) return const FinnhubResult.err('Finnhub API key is not configured.');
    try {
      final res = await _http
          .get(_uri('/api/v1/quote', {'symbol': symbol}))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        return FinnhubResult.err('Finnhub quote request failed (${res.statusCode}).');
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final quote = Quote(
        current: (json['c'] as num?)?.toDouble() ?? 0.0,
        change: (json['d'] as num?)?.toDouble() ?? 0.0,
        percent: (json['dp'] as num?)?.toDouble() ?? 0.0,
        high: (json['h'] as num?)?.toDouble() ?? 0.0,
        low: (json['l'] as num?)?.toDouble() ?? 0.0,
        open: (json['o'] as num?)?.toDouble() ?? 0.0,
        previousClose: (json['pc'] as num?)?.toDouble() ?? 0.0,
      );
      return quote.isValid ? FinnhubResult.ok(quote) : const FinnhubResult.err('No quote data.');
    } catch (e) {
      return FinnhubResult.err('Finnhub quote request failed: $e');
    }
  }

  Future<FinnhubResult<CompanyProfile>> fetchProfile(String symbol) async {
    if (!hasApiKey) return const FinnhubResult.err('Finnhub API key is not configured.');
    try {
      final res = await _http
          .get(_uri('/api/v1/stock/profile2', {'symbol': symbol}))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        return FinnhubResult.err('Finnhub profile request failed (${res.statusCode}).');
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final profile = CompanyProfile(
        name: json['name'] as String? ?? '',
        exchange: json['exchange'] as String? ?? '',
        currency: json['currency'] as String? ?? '',
        marketCap: (json['marketCapitalization'] as num?)?.toDouble() ?? 0.0,
      );
      return profile.isValid
          ? FinnhubResult.ok(profile)
          : const FinnhubResult.err('No profile data.');
    } catch (e) {
      return FinnhubResult.err('Finnhub profile request failed: $e');
    }
  }

  Future<FinnhubResult<List<Candle>>> fetchCandles(String symbol, Timeframe timeframe) async {
    if (!hasApiKey) return const FinnhubResult.err('Finnhub API key is not configured.');
    final to = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final from = to - timeframe.lookbackDays * 24 * 60 * 60;
    try {
      final res = await _http.get(_uri('/api/v1/stock/candle', {
        'symbol': symbol,
        'resolution': timeframe.resolution,
        'from': '$from',
        'to': '$to',
      })).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        return FinnhubResult.err('Finnhub candle request failed (${res.statusCode}).');
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['s'] != 'ok') {
        return const FinnhubResult.err('No chart data returned.');
      }
      final times = (json['t'] as List).cast<num>();
      final opens = (json['o'] as List).cast<num>();
      final highs = (json['h'] as List).cast<num>();
      final lows = (json['l'] as List).cast<num>();
      final closes = (json['c'] as List).cast<num>();
      final volumes = (json['v'] as List).cast<num>();
      final count = [times, opens, highs, lows, closes, volumes].map((l) => l.length).reduce((a, b) => a < b ? a : b);

      final candles = <Candle>[
        for (var i = 0; i < count; i++)
          Candle(
            time: times[i].toInt(),
            open: opens[i].toDouble(),
            high: highs[i].toDouble(),
            low: lows[i].toDouble(),
            close: closes[i].toDouble(),
            volume: volumes[i].toDouble(),
          ),
      ];
      return candles.isNotEmpty
          ? FinnhubResult.ok(candles)
          : const FinnhubResult.err('No chart data returned.');
    } catch (e) {
      return FinnhubResult.err('Finnhub candle request failed: $e');
    }
  }

  void close() => _http.close();
}
