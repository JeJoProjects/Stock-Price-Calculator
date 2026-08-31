/// Ported from scripts/search_symbols.py's Yahoo Finance bridge, moved
/// server-side per the migration plan (no more shelling out to a
/// hardcoded python.exe path from the client). The offline fallback that
/// script had isn't needed here — the Flutter client already does its own
/// offline scoring over the bundled ticker list; this only supplements it.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

class OnlineSymbolResult {
  final String symbol;
  final String name;
  final String exchange;
  const OnlineSymbolResult({required this.symbol, required this.name, required this.exchange});

  Map<String, dynamic> toJson() => {'symbol': symbol, 'name': name, 'exchange': exchange};
}

class SymbolSearchClient {
  final http.Client _http;
  SymbolSearchClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Future<List<OnlineSymbolResult>> search(String query, {int maxResults = 12}) async {
    final uri = Uri.https('query2.finance.yahoo.com', '/v1/finance/search', {
      'q': query,
      'quotesCount': '$maxResults',
      'newsCount': '0',
      'listsCount': '0',
      'enableFuzzyQuery': 'false',
      'quotesQueryId': 'tss_match_phrase_query',
    });
    try {
      final res = await _http
          .get(uri, headers: {'User-Agent': 'StockCalc/3.0'})
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return const [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final quotes = (json['quotes'] as List?) ?? const [];
      final results = <OnlineSymbolResult>[];
      for (final q in quotes) {
        final quote = q as Map<String, dynamic>;
        final type = quote['quoteType'] as String?;
        if (type != 'EQUITY' && type != 'ETF') continue;
        results.add(OnlineSymbolResult(
          symbol: quote['symbol'] as String? ?? '',
          name: (quote['shortname'] ?? quote['longname'] ?? '') as String,
          exchange: quote['exchange'] as String? ?? '',
        ));
        if (results.length >= maxResults) break;
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  void close() => _http.close();
}
