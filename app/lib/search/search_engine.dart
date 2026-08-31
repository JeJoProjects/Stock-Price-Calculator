/// Ported from src/search/stockSearchEngine.cpp's offline scoring ladder.
/// The old code split this into a binary-search prefix pass + a linear
/// substring pass for performance over a sorted array; with ~200 bundled
/// tickers a single linear pass with the same priority ordering produces
/// identical results with far less code.
library;

import 'ticker_data.dart';

enum MatchKind { exactSymbol, prefixSymbol, symbolSubstring, prefixName, nameSubstring, online }

extension MatchKindInfo on MatchKind {
  int get score => switch (this) {
        MatchKind.online => 200,
        MatchKind.exactSymbol => 130,
        MatchKind.prefixSymbol => 120,
        MatchKind.symbolSubstring => 90,
        MatchKind.prefixName => 70,
        MatchKind.nameSubstring => 55,
      };

  String get preview => switch (this) {
        MatchKind.online => 'Online result',
        MatchKind.exactSymbol => 'Exact symbol',
        MatchKind.prefixSymbol => 'Symbol prefix',
        MatchKind.symbolSubstring => 'Symbol contains query',
        MatchKind.prefixName => 'Company name prefix',
        MatchKind.nameSubstring => 'Company name contains query',
      };
}

class SearchResult {
  final TickerEntry entry;
  final MatchKind kind;
  const SearchResult({required this.entry, required this.kind});
  int get score => kind.score;
  String get preview => kind.preview;
}

bool _startsWithWord(String name, String query) {
  final idx = name.indexOf(query);
  if (idx == -1) return false;
  if (idx == 0) return true;
  final prev = name[idx - 1];
  return !RegExp(r'[a-z0-9]').hasMatch(prev);
}

class SearchEngine {
  final List<TickerEntry> tickers;
  final Map<String, List<SearchResult>> _cache = {};

  SearchEngine(this.tickers);

  int get tickerCount => tickers.length;

  List<SearchResult> search(String rawQuery, {int maxResults = 12}) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return const [];

    final cacheKey = '$query|$maxResults';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    if (_cache.length > 96) _cache.clear();

    final results = <SearchResult>[];
    for (final t in tickers) {
      MatchKind? kind;
      if (t.symbolLower == query) {
        kind = MatchKind.exactSymbol;
      } else if (t.symbolLower.startsWith(query)) {
        kind = MatchKind.prefixSymbol;
      } else if (t.symbolLower.contains(query)) {
        kind = MatchKind.symbolSubstring;
      } else if (_startsWithWord(t.nameLower, query)) {
        kind = MatchKind.prefixName;
      } else if (t.nameLower.contains(query)) {
        kind = MatchKind.nameSubstring;
      }
      if (kind != null) results.add(SearchResult(entry: t, kind: kind));
    }

    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.entry.symbol.compareTo(b.entry.symbol);
    });

    final truncated = results.take(maxResults).toList();
    _cache[cacheKey] = truncated;
    return truncated;
  }
}

/// Ported from Application::mergeOnlineResults (application.cpp:1323-1351):
/// online results go on top, deduped by symbol against what's already
/// shown, capped to maxResults.
List<SearchResult> mergeOnlineResults(
  List<SearchResult> offlineResults,
  List<TickerEntry> onlineEntries, {
  int maxResults = 12,
}) {
  final existingSymbols = offlineResults.map((r) => r.entry.symbolLower).toSet();
  final onlineResults = <SearchResult>[];
  for (final entry in onlineEntries) {
    if (existingSymbols.contains(entry.symbolLower)) continue;
    existingSymbols.add(entry.symbolLower);
    onlineResults.add(SearchResult(entry: entry, kind: MatchKind.online));
  }
  return [...onlineResults, ...offlineResults].take(maxResults).toList();
}
