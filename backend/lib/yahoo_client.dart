/// Fetches Yahoo Finance's "day gainers" predefined screener via its own
/// JSON API - the same endpoint https://finance.yahoo.com/markets/stocks/gainers/
/// itself calls - rather than scraping that page's rendered HTML. Verified
/// against a live fetch while building this: GET
/// https://query1.finance.yahoo.com/v1/finance/screener/predefined/saved
/// ?scrIds=day_gainers&count=25&lang=en-US&region=US returns
/// `{finance: {result: [{quotes: [...]}]}}`, unauthenticated, no key needed.
///
/// Unlike finviz_client.dart this is JSON, not HTML - no markup-parsing
/// fragility and no risk of the page being client-side (JS) rendered.
/// `formatted=true` style requests can wrap numeric fields as
/// `{raw, fmt}` instead of a bare number depending on Yahoo's mood, so
/// [_asDouble] below accepts either shape.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

class YahooRow {
  final String symbol;
  final String company;
  final String exchange;
  final double marketCap;
  final double price;
  final double changePercent;
  final double volume;

  const YahooRow({
    required this.symbol,
    required this.company,
    this.exchange = '',
    required this.marketCap,
    required this.price,
    required this.changePercent,
    required this.volume,
  });
}

class YahooClient {
  final http.Client _http;

  YahooClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  /// Mirrors https://finance.yahoo.com/markets/stocks/gainers/ (top movers by
  /// descending % change, Yahoo's "day_gainers" predefined screen).
  Future<List<YahooRow>> fetchTopGainers() async {
    final uri = Uri.https('query1.finance.yahoo.com', '/v1/finance/screener/predefined/saved', {
      'lang': 'en-US',
      'region': 'US',
      'scrIds': 'day_gainers',
      'count': '25',
    });
    final res = await _http.get(uri, headers: {
      // Same defensive header as finviz_client.dart - some Yahoo endpoints
      // reject requests with no User-Agent.
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/128.0.0.0 Safari/537.36',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw StateError('Yahoo screener request failed (${res.statusCode}).');
    }

    late final Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } on FormatException {
      throw StateError(
          'Yahoo screener response was not JSON - it may have changed, or the request was blocked.');
    }

    final results = (body['finance'] as Map<String, dynamic>?)?['result'] as List?;
    if (results == null || results.isEmpty) {
      throw StateError('Yahoo screener response structure not recognized - it may have changed.');
    }
    final quotes = (results.first as Map<String, dynamic>)['quotes'] as List? ?? const [];

    final rows = <YahooRow>[];
    for (final q in quotes) {
      final quote = q as Map<String, dynamic>;
      final symbol = (quote['symbol'] as String? ?? '').trim();
      if (symbol.isEmpty) continue;
      rows.add(YahooRow(
        symbol: symbol,
        company: (quote['longName'] ?? quote['shortName'] ?? symbol) as String,
        exchange: (quote['fullExchangeName'] ?? quote['exchange'] ?? '') as String,
        marketCap: _asDouble(quote['marketCap']),
        price: _asDouble(quote['regularMarketPrice']),
        changePercent: _asDouble(quote['regularMarketChangePercent']),
        volume: _asDouble(quote['regularMarketVolume']),
      ));
    }
    return rows;
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is Map && value['raw'] is num) return (value['raw'] as num).toDouble();
    return 0.0;
  }

  void close() => _http.close();
}
