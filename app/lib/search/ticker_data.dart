/// Ported from src/search/tickerData.hpp/.cpp, but loaded via the bundled
/// Flutter asset + a real JSON decoder instead of the old hand-rolled
/// brace-scanning parser.
library;

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class TickerEntry {
  final String symbol;
  final String name;
  final String exchange;
  final String symbolLower;
  final String nameLower;

  TickerEntry({required this.symbol, required this.name, required this.exchange})
      : symbolLower = symbol.toLowerCase(),
        nameLower = name.toLowerCase();
}

Future<List<TickerEntry>> loadTickerUniverse() async {
  final raw = await rootBundle.loadString('assets/data/us_tickers_full.json');
  final list = jsonDecode(raw) as List;
  final tickers = [
    for (final entry in list)
      TickerEntry(
        symbol: entry['symbol'] as String,
        name: entry['name'] as String,
        exchange: entry['exchange'] as String,
      ),
  ];
  tickers.sort((a, b) => a.symbolLower.compareTo(b.symbolLower));
  return tickers;
}
