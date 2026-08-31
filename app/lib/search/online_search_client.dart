/// Queries the Dart backend's /search endpoint (which bridges to Yahoo
/// Finance - see backend/lib/symbol_search.dart), replacing the old app's
/// Python-subprocess bridge entirely. Debounced by the caller, same as the
/// old app's 0.18s idle-before-firing behavior.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ticker_data.dart';

class OnlineSearchClient {
  final String baseUrl;
  final http.Client _http;

  OnlineSearchClient({this.baseUrl = 'http://localhost:8090', http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  Future<List<TickerEntry>> search(String query, {int maxResults = 12}) async {
    if (query.trim().length < 2) return const [];
    try {
      final uri = Uri.parse('$baseUrl/search?q=${Uri.encodeQueryComponent(query)}&max=$maxResults');
      final res = await _http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return const [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (json['results'] as List?) ?? const [];
      return [
        for (final r in results)
          TickerEntry(
            symbol: r['symbol'] as String,
            name: r['name'] as String,
            exchange: r['exchange'] as String,
          ),
      ].where((t) => t.symbol.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  void close() => _http.close();
}
