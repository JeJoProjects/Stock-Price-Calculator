/// Free-tier OHLC candle source, replacing Finnhub's /stock/candle (now
/// paywalled on newer accounts - see finnhub_client.dart's KNOWN RISK note,
/// which is why the chart pane always showed "No chart data returned.").
///
/// Alpha Vantage's free tier is a plain email signup, no credit card - but
/// the trade-off is an extremely tight quota (~25 requests/day per key as
/// of 2024/2025). See candle_cache.dart for how that budget is protected
/// across app restarts, and _requestParamsFor below for the per-timeframe
/// coverage caveats this constraint forces.
///
/// Docs: https://www.alphavantage.co/documentation/#time-series
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'market_types.dart';

class AlphaVantageResult<T> {
  final T? value;
  final String? error;
  final bool rateLimited;
  const AlphaVantageResult.ok(this.value)
      : error = null,
        rateLimited = false;
  const AlphaVantageResult.err(this.error, {this.rateLimited = false}) : value = null;
  bool get isOk => value != null;
}

class AlphaVantageClient {
  final String apiKey;
  final http.Client _http;

  AlphaVantageClient({required this.apiKey, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  bool get hasApiKey => apiKey.isNotEmpty;

  Future<AlphaVantageResult<List<Candle>>> fetchCandles(String symbol, Timeframe timeframe) async {
    if (!hasApiKey) {
      return const AlphaVantageResult.err('Alpha Vantage API key is not configured.');
    }
    final (function, params) = _requestParamsFor(timeframe);
    final uri = Uri.https('www.alphavantage.co', '/query', {
      'function': function,
      'symbol': symbol,
      'apikey': apiKey,
      ...params,
    });
    try {
      final res = await _http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        return AlphaVantageResult.err('Alpha Vantage request failed (${res.statusCode}).');
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;

      if (json.containsKey('Error Message')) {
        return AlphaVantageResult.err(json['Error Message'] as String);
      }
      if (json.containsKey('Note') || json.containsKey('Information')) {
        // This is how Alpha Vantage reports "you've hit your per-minute or
        // daily quota" - a 200 response with one of these keys instead of
        // a "Time Series ..." key, not a distinct HTTP status. Flagged
        // separately so the UI can say "try again later" instead of a
        // generic error.
        final msg = (json['Note'] ?? json['Information']) as String;
        return AlphaVantageResult.err(
          'Alpha Vantage free-tier limit reached - try again later. ($msg)',
          rateLimited: true,
        );
      }

      final seriesKey = json.keys.firstWhere((k) => k.startsWith('Time Series'), orElse: () => '');
      if (seriesKey.isEmpty) {
        return const AlphaVantageResult.err('No chart data returned.');
      }
      final series = json[seriesKey] as Map<String, dynamic>;
      final candles = series.entries.map((e) {
        final v = e.value as Map<String, dynamic>;
        return Candle(
          time: _parseEasternNaive(e.key).millisecondsSinceEpoch ~/ 1000,
          open: double.parse(v['1. open'] as String),
          high: double.parse(v['2. high'] as String),
          low: double.parse(v['3. low'] as String),
          close: double.parse(v['4. close'] as String),
          volume: double.parse((v['5. volume'] as String?) ?? '0'),
        );
      }).toList()
        ..sort((a, b) => a.time.compareTo(b.time));

      if (candles.isEmpty) {
        return const AlphaVantageResult.err('No chart data returned.');
      }
      return AlphaVantageResult.ok(_trimToTimeframe(candles, timeframe));
    } catch (e) {
      return AlphaVantageResult.err('Alpha Vantage request failed: $e');
    }
  }

  /// Maps our Timeframe to Alpha Vantage's function/interval/outputsize.
  /// Free-tier caveat worth knowing: TIME_SERIES_DAILY's `outputsize=full`
  /// is premium-only, so month6/year1/max are all capped at the free
  /// `compact` size (the latest ~100 trading days, ~4-5 months) regardless
  /// of how far back the user asks to see - there's no free way around
  /// this short of stitching together many `month=` intraday calls, which
  /// would blow the daily quota instantly for one chart load.
  (String, Map<String, String>) _requestParamsFor(Timeframe timeframe) {
    switch (timeframe) {
      case Timeframe.day1:
        return ('TIME_SERIES_INTRADAY', {'interval': '5min', 'extended_hours': 'true', 'outputsize': 'full'});
      case Timeframe.week1:
        return ('TIME_SERIES_INTRADAY', {'interval': '15min', 'extended_hours': 'true', 'outputsize': 'full'});
      case Timeframe.month1:
        return ('TIME_SERIES_INTRADAY', {'interval': '60min', 'extended_hours': 'true', 'outputsize': 'full'});
      case Timeframe.month6:
      case Timeframe.year1:
      case Timeframe.max:
        return ('TIME_SERIES_DAILY', {'outputsize': 'compact'});
    }
  }

  /// For day1/week1, intraday `outputsize=full` returns up to 30 days of
  /// bars in one API call - trim down to just the window the timeframe
  /// asks for so "1D" doesn't render a month of 5-minute candles.
  List<Candle> _trimToTimeframe(List<Candle> candles, Timeframe timeframe) {
    switch (timeframe) {
      case Timeframe.day1:
        // Keep only the single most recent trading day present in the
        // data (grouped by Eastern calendar date, since that's the
        // timezone Alpha Vantage labels its timestamps in).
        final lastDate = _easternDateLabel(candles.last.time);
        return candles.where((c) => _easternDateLabel(c.time) == lastDate).toList();
      case Timeframe.week1:
        final cutoff = candles.last.time - 7 * 24 * 60 * 60;
        return candles.where((c) => c.time >= cutoff).toList();
      case Timeframe.month1:
      case Timeframe.month6:
      case Timeframe.year1:
      case Timeframe.max:
        return candles;
    }
  }

  String _easternDateLabel(int epochSeconds) {
    final utc = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000, isUtc: true);
    final eastern = utc.subtract(const Duration(hours: 5));
    return '${eastern.year}-${eastern.month}-${eastern.day}';
  }

  /// Alpha Vantage returns naive "yyyy-MM-dd[ HH:mm:ss]" strings labeled as
  /// US/Eastern (its "Meta Data" always reports "6. Time Zone":
  /// "US/Eastern"). Dart has no bundled IANA timezone database, and pulling
  /// in the `timezone` package for one field is overkill here - this
  /// approximates with a fixed EST (UTC-5) offset year-round, so candle
  /// times can be up to 1h off during EDT (roughly March-November). That
  /// only shifts the hover tooltip's displayed time, not price values or
  /// candle ordering.
  DateTime _parseEasternNaive(String raw) {
    final parts = raw.split(' ');
    final dateParts = parts[0].split('-').map(int.parse).toList();
    final timeParts = parts.length > 1 ? parts[1].split(':').map(int.parse).toList() : [0, 0, 0];
    return DateTime.utc(
      dateParts[0],
      dateParts[1],
      dateParts[2],
      timeParts[0],
      timeParts[1],
      timeParts.length > 2 ? timeParts[2] : 0,
    ).add(const Duration(hours: 5));
  }

  void close() => _http.close();
}
