// Ported scoring ladder from src/search/stockSearchEngine.cpp:
// exact symbol > prefix symbol > symbol substring > name-prefix-word > name substring.
import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/search/search_engine.dart';
import 'package:stockcalc/search/ticker_data.dart';

SearchEngine _engineWith(List<(String, String, String)> rows) {
  final tickers = [
    for (final (symbol, name, exchange) in rows)
      TickerEntry(symbol: symbol, name: name, exchange: exchange),
  ];
  return SearchEngine(tickers);
}

void main() {
  final engine = _engineWith([
    ('AAPL', 'Apple Inc', 'NASDAQ'),
    ('AAPX', 'Applied Signal Technology', 'NYSE'),
    ('MSFT', 'Microsoft Corporation', 'NASDAQ'),
    ('GOOG', 'Alphabet Inc (Google)', 'NASDAQ'),
  ]);

  test('exact symbol match ranks first', () {
    final results = engine.search('AAPL');
    expect(results.first.entry.symbol, 'AAPL');
    expect(results.first.kind, MatchKind.exactSymbol);
  });

  test('prefix symbol match ranks above substring matches', () {
    final results = engine.search('AAP');
    expect(results.map((r) => r.entry.symbol).toList(), ['AAPL', 'AAPX']);
    expect(results.every((r) => r.kind == MatchKind.prefixSymbol), true);
  });

  test('word-boundary name match finds Google via Alphabet entry', () {
    // "(Google)" - the '(' is a non-alnum boundary, so this is a prefixName
    // word-boundary match, ranked above a plain nameSubstring match.
    final results = engine.search('google');
    expect(results.first.entry.symbol, 'GOOG');
    expect(results.first.kind, MatchKind.prefixName);
  });

  test('plain substring match (no word boundary) is nameSubstring', () {
    final results = engine.search('lphabet');
    expect(results.first.entry.symbol, 'GOOG');
    expect(results.first.kind, MatchKind.nameSubstring);
  });

  test('empty query returns no results', () {
    expect(engine.search(''), isEmpty);
  });

  test('maxResults truncates the result list', () {
    final results = engine.search('a', maxResults: 1);
    expect(results.length, 1);
  });

  test('mergeOnlineResults puts online results on top and dedupes by symbol', () {
    final offline = engine.search('AAP'); // AAPL, AAPX
    final online = [
      TickerEntry(symbol: 'AAPL', name: 'Apple Inc (duplicate)', exchange: 'NASDAQ'),
      TickerEntry(symbol: 'AAOI', name: 'Applied Optoelectronics', exchange: 'NASDAQ'),
    ];
    final merged = mergeOnlineResults(offline, online, maxResults: 12);
    // AAPL from `online` is dropped (already in offline); AAOI is new and goes on top.
    expect(merged.map((r) => r.entry.symbol).toList(), ['AAOI', 'AAPL', 'AAPX']);
    expect(merged.first.kind, MatchKind.online);
  });

  test('mergeOnlineResults respects maxResults', () {
    final offline = engine.search('AAP');
    final online = [TickerEntry(symbol: 'AAOI', name: 'Applied Optoelectronics', exchange: 'NASDAQ')];
    final merged = mergeOnlineResults(offline, online, maxResults: 1);
    expect(merged.length, 1);
    expect(merged.first.entry.symbol, 'AAOI');
  });
}
