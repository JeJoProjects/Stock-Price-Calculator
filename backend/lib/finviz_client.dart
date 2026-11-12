/// Fetches Finviz's free, publicly viewable stock screener
/// (https://finviz.com/screener/stocks?...) - no login, not the paid Elite
/// export API.
///
/// Finviz's late-2026 redesign replaced the old `tr.styled-row` HTML table
/// with a client-rendered grid, but the page still ships the table data as
/// JSON inside `<script type="application/json" data-ssr-props=...>` (server
/// side rendering "island"). Parsing that JSON is far more robust than
/// scraping cells, and the custom view (`v=152&c=...`) adds the columns a
/// momentum scanner needs: float, relative/average volume, gap, open, RSI,
/// short float.
///
/// This is still scraping, not an official integration, and Finviz's free
/// quotes are DELAYED - so the live scanner only uses Finviz to decide WHICH
/// stocks belong on the screen (refreshed about once a minute, pages fetched
/// one at a time with a pause), and takes live prices from Yahoo's streaming
/// feed (see yahoo_stream.dart). Never poll Finviz every second: it would be
/// both pointless (delayed data) and quickly blocked.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

class FinvizRow {
  final String symbol;
  final String company;
  final String sector;
  final String industry;
  final String country;

  /// Dollars (Finviz reports millions; converted here).
  final double marketCap;
  final double price;
  final double changePercent;
  final double volume;
  final double prevClose;
  final double open;

  /// Opening gap vs previous close, in percent.
  final double gapPercent;

  /// Change since the open, in percent.
  final double changeFromOpenPercent;

  /// Finviz's time-of-day-normalised relative volume (1.0 = normal).
  final double relativeVolume;
  final double averageVolume;

  /// Shares (Finviz reports millions; converted here). 0 = unknown.
  final double floatShares;

  /// Short interest as a percent of float. 0 = unknown.
  final double shortFloatPercent;
  final double rsi;

  const FinvizRow({
    required this.symbol,
    required this.company,
    this.sector = '',
    this.industry = '',
    this.country = '',
    required this.marketCap,
    required this.price,
    required this.changePercent,
    required this.volume,
    this.prevClose = 0,
    this.open = 0,
    this.gapPercent = 0,
    this.changeFromOpenPercent = 0,
    this.relativeVolume = 0,
    this.averageVolume = 0,
    this.floatShares = 0,
    this.shortFloatPercent = 0,
    this.rsi = 0,
  });
}

/// One page of a screen, plus how many matches exist in total.
class FinvizPage {
  final List<FinvizRow> rows;
  final int totalCount;
  final int firstRow;
  final int pageSize;
  const FinvizPage(this.rows, this.totalCount, this.firstRow, this.pageSize);
}

class FinvizClient {
  final http.Client _http;

  /// Pause between page requests of one scan (politeness / anti-blocking).
  final Duration pageDelay;

  FinvizClient({http.Client? httpClient, this.pageDelay = const Duration(milliseconds: 700)})
      : _http = httpClient ?? http.Client();

  /// Custom-view column ids: ticker, company, sector, industry, country,
  /// market cap, float (25), short float (30), RSI/change-from-open/gap/open
  /// (59-62), average volume, relative volume, price, change, volume (63-67).
  /// Verified against live pages; each id adds its fields to the row JSON.
  static const columns = '1,2,3,4,5,6,25,30,59,60,61,62,63,64,65,66,67';

  static const _headers = {
    // Finviz blocks requests that look like bots (no browser UA / Accept).
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// One page of a screen. [signal] is Finviz's `s=` value (e.g.
  /// `ta_unusualvolume`), [filters] its `f=` value, [firstRow] is 1-based.
  Future<FinvizPage> fetchPage({
    String signal = 'ta_unusualvolume',
    String filters = '',
    String order = '-change',
    int firstRow = 1,
  }) async {
    final uri = Uri.https('finviz.com', '/screener/stocks', {
      'v': '152',
      if (signal.isNotEmpty) 's': signal,
      if (filters.isNotEmpty) 'f': filters,
      'o': order,
      'c': columns,
      if (firstRow > 1) 'r': '$firstRow',
    });
    final res = await _http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (res.statusCode == 429) {
      throw const FinvizRateLimited();
    }
    if (res.statusCode != 200) {
      throw StateError('Finviz screener request failed (${res.statusCode}).');
    }
    return parsePage(res.body);
  }

  /// Every page of a screen, up to [maxPages], fetched one after another.
  Future<List<FinvizRow>> fetchAll({
    String signal = 'ta_unusualvolume',
    String filters = '',
    String order = '-change',
    int maxPages = 10,
  }) async {
    final first = await fetchPage(signal: signal, filters: filters, order: order);
    final rows = [...first.rows];
    final pageSize = first.pageSize > 0 ? first.pageSize : 20;
    final pages = ((first.totalCount + pageSize - 1) ~/ pageSize).clamp(1, maxPages);
    for (var p = 1; p < pages; p++) {
      await Future<void>.delayed(pageDelay);
      final page = await fetchPage(signal: signal, filters: filters, order: order, firstRow: p * pageSize + 1);
      if (page.rows.isEmpty) break;
      rows.addAll(page.rows);
    }
    return rows;
  }

  /// Backwards-compatible entry point for the screener rail: page 1 of the
  /// unusual-volume screen, sorted by descending change.
  Future<List<FinvizRow>> fetchUnusualVolumeMovers() async => (await fetchPage()).rows;

  static final _islandRe = RegExp(
    r'<script type="application/json" data-ssr-props="[^"]*">(.*?)</script>',
    dotAll: true,
  );

  /// Parses the SSR JSON island of a screener page.
  static FinvizPage parsePage(String body) {
    for (final m in _islandRe.allMatches(body)) {
      final Object? json;
      try {
        json = jsonDecode(m.group(1)!);
      } on FormatException {
        continue;
      }
      if (json is! Map<String, dynamic>) continue;
      final data = json['data'];
      if (data is! Map<String, dynamic> || data['rows'] is! List) continue;
      final rows = <FinvizRow>[];
      for (final r in (data['rows'] as List).whereType<Map<String, dynamic>>()) {
        final row = _row(r);
        if (row != null) rows.add(row);
      }
      return FinvizPage(
        rows,
        (data['totalCount'] as num?)?.toInt() ?? rows.length,
        (data['firstRow'] as num?)?.toInt() ?? 0,
        (data['pageSize'] as num?)?.toInt() ?? rows.length,
      );
    }
    throw StateError('Finviz screener page structure not recognized - it may have changed, or the request was '
        'blocked (no screener data island found).');
  }

  static FinvizRow? _row(Map<String, dynamic> r) {
    final t = (r['text'] as Map?)?.cast<String, dynamic>() ?? const {};
    final n = (r['numbers'] as Map?)?.cast<String, dynamic>() ?? const {};
    final symbol = (t['ticker'] as String? ?? '').trim();
    if (symbol.isEmpty) return null;
    double d(String k) => (n[k] as num?)?.toDouble() ?? 0;
    return FinvizRow(
      symbol: symbol,
      company: t['company'] as String? ?? '',
      sector: t['sector'] as String? ?? '',
      industry: t['industry'] as String? ?? '',
      country: t['country'] as String? ?? '',
      marketCap: d('marketCap') * 1e6,
      price: d('price'),
      changePercent: d('change'),
      volume: d('volume'),
      prevClose: d('prevClose'),
      open: d('open'),
      gapPercent: d('gap'),
      changeFromOpenPercent: d('changeopen'),
      relativeVolume: d('relativeVolume'),
      averageVolume: d('averageVolume'),
      floatShares: d('sharesFloat') * 1e6,
      shortFloatPercent: d('shortInterestShare'),
      rsi: d('rsi'),
    );
  }

  void close() => _http.close();
}

/// Finviz answered 429 Too Many Requests: back off before trying again.
class FinvizRateLimited implements Exception {
  const FinvizRateLimited();
  @override
  String toString() => 'Finviz is rate-limiting requests (HTTP 429) - backing off.';
}
