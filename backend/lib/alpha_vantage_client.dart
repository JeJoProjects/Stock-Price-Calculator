/// Free-tier OHLC candle source, replacing Finnhub's /stock/candle (now
/// paywalled on newer accounts - see finnhub_client.dart's KNOWN RISK note,
/// which is why the chart pane always showed "No chart data returned.").
///
/// Alpha Vantage's free tier is a plain email signup, no credit card - but
/// two real constraints shape everything below, the second one discovered
/// by hitting the live API directly (not just reading the docs, which are
/// stale on this point):
///
/// 1. An extremely tight quota (~25 requests/day per key). See
///    candle_cache.dart for how that budget is protected across app
///    restarts.
/// 2. **TIME_SERIES_INTRADAY is premium-only on current free keys**,
///    confirmed via a live request on 2026-10-04 ("This is a premium
///    endpoint..."), regardless of `extended_hours`/`outputsize` - contrary
///    to the publicly documented params list, which still describes
///    `extended_hours` as a plain optional param. Alpha Vantage has
///    evidently tightened the free tier since that page was written.
///    **Only `TIME_SERIES_DAILY` (and `GLOBAL_QUOTE`, unused here) are
///    confirmed free.** So every timeframe below uses daily bars - there is
///    no free source of intraday or extended-hours (pre/post-market) data
///    from this provider, or (per CLAUDE.md's Candle Data section) from any
///    other free provider either. If Alpha Vantage ever re-opens intraday
///    on free keys, `_requestParamsFor`/`_trimToTimeframe` are the two
///    places to revisit.
///
/// Docs (aspirational for intraday, accurate for daily):
/// https://www.alphavantage.co/documentation/#time-series
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

  /// Every timeframe maps to the same TIME_SERIES_DAILY/compact request -
  /// see the library doc comment above for why (TIME_SERIES_INTRADAY is
  /// premium-only on current free keys, confirmed against the live API,
  /// despite what the public docs say). `outputsize=full` is separately
  /// documented as premium-only for this endpoint, so `compact` (the
  /// latest ~100 trading days, ~4-5 months) is the ceiling regardless of
  /// which timeframe is requested - `_trimToTimeframe` below just decides
  /// how much of that same ~100-day window to show for each one.
  (String, Map<String, String>) _requestParamsFor(Timeframe timeframe) {
    return ('TIME_SERIES_DAILY', {'outputsize': 'compact'});
  }

  /// All timeframes draw from the same ~100 daily bars (see
  /// _requestParamsFor) - this just trims the tail to a plausible window
  /// per label, since there's no finer (intraday) granularity available
  /// for free. day1 in particular is a known honest degradation: it shows
  /// only the single most recent daily candle, not an intraday session -
  /// there is currently no free way to show real intraday movement.
  List<Candle> _trimToTimeframe(List<Candle> candles, Timeframe timeframe) {
    final int tail;
    switch (timeframe) {
      case Timeframe.day1:
        tail = 1;
      case Timeframe.week1:
        tail = 5; // ~1 trading week
      case Timeframe.month1:
        tail = 21; // ~1 trading month
      case Timeframe.month6:
      case Timeframe.year1:
      case Timeframe.max:
        tail = candles.length; // take everything compact returned
    }
    if (tail >= candles.length) return candles;
    return candles.sublist(candles.length - tail);
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
