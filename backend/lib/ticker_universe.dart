/// Loads the shared data/us_tickers_full.json (same file the Flutter client
/// bundles for search) as the candidate universe the screener polls.
/// Finnhub has no screener/full-market-snapshot endpoint on the free tier,
/// so we poll this bounded, known list rather than the whole market — see
/// ScreenerService's rate-limiting notes.
library;

import 'dart:convert';
import 'dart:io';

class TickerInfo {
  final String symbol;
  final String name;
  final String exchange;
  const TickerInfo({required this.symbol, required this.name, required this.exchange});
}

List<TickerInfo> loadTickerUniverse() {
  final candidates = [
    File.fromUri(Platform.script.resolve('../../data/us_tickers_full.json')),
    File('data/us_tickers_full.json'),
    File('../data/us_tickers_full.json'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      final list = jsonDecode(file.readAsStringSync()) as List;
      return [
        for (final entry in list)
          TickerInfo(
            symbol: entry['symbol'] as String,
            name: entry['name'] as String,
            exchange: entry['exchange'] as String,
          ),
      ];
    }
  }
  throw StateError('Could not find data/us_tickers_full.json from any candidate path.');
}
