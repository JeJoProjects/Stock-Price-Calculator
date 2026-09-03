/// Fetches https://finviz.com/screener?v=111&s=ta_unusualvolume&o=-change
/// directly - the free, publicly viewable screener page, not the paid Elite
/// export API. Finviz gates their CSV/API export behind an Elite
/// subscription, but the page itself needs no login to view, so this
/// parses the same HTML table a browser would render.
///
/// This is scraping, not an official/sanctioned integration: it depends on
/// Finviz's current markup (verified against a live fetch while building
/// this - see the column order below) and sits outside what most sites'
/// terms permit for automated/bot traffic. Kept deliberately light-touch to
/// stay a reasonable, low-frequency personal-use fetch: one request per
/// poll cycle for the first page only (top 20, already sorted by
/// descending % change - the most extreme movers), not a crawl of the
/// ~200-row result set across every page.
library;

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class FinvizRow {
  final String symbol;
  final String company;
  final String sector;
  final String industry;
  final double marketCap;
  final double price;
  final double changePercent;
  final double volume;

  const FinvizRow({
    required this.symbol,
    required this.company,
    this.sector = '',
    this.industry = '',
    required this.marketCap,
    required this.price,
    required this.changePercent,
    required this.volume,
  });
}

class FinvizClient {
  final http.Client _http;

  FinvizClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  /// Mirrors https://finviz.com/screener?v=111&s=ta_unusualvolume&o=-change
  /// (page 1 - top 20 by descending change).
  Future<List<FinvizRow>> fetchUnusualVolumeMovers() async {
    final uri = Uri.https('finviz.com', '/screener', {
      'v': '111',
      's': 'ta_unusualvolume',
      'o': '-change',
    });
    final res = await _http.get(uri, headers: {
      // Finviz returns an empty/blocked response to requests that look
      // like bots (no User-Agent, non-browser Accept headers).
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/128.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    }).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw StateError('Finviz screener request failed (${res.statusCode}).');
    }
    final rows = _parseRows(res.body);
    if (rows.isEmpty && !res.body.contains('screener_table')) {
      throw StateError('Finviz screener page structure not recognized - it may have changed, or '
          'the request was blocked.');
    }
    return rows;
  }

  List<FinvizRow> _parseRows(String htmlBody) {
    final document = html_parser.parse(htmlBody);
    final dataRows = document.querySelectorAll('tr.styled-row');
    final rows = <FinvizRow>[];
    for (final row in dataRows) {
      final cells = row.querySelectorAll('td');
      // No.,Ticker,Company,Sector,Industry,Country,Market Cap,P/E,Price,
      // Change %,Volume - confirmed against a live fetch of this exact URL.
      if (cells.length < 11) continue;
      String cellText(int i) => cells[i].text.trim();
      // The ticker cell also holds a one-letter logo-fallback avatar, so
      // its raw .text is polluted (e.g. "TTRBG") - pull the clean symbol
      // from the dedicated ticker link instead.
      final symbol = (row.querySelector('a.tab-link')?.text ?? cellText(1)).trim();
      if (symbol.isEmpty) continue;
      rows.add(FinvizRow(
        symbol: symbol,
        company: cellText(2),
        sector: cellText(3),
        industry: cellText(4),
        marketCap: _parseCompactNumber(cellText(6)),
        price: _parseCompactNumber(cellText(8)),
        changePercent: _parseCompactNumber(cellText(9).replaceAll('%', '')),
        volume: _parseCompactNumber(cellText(10)),
      ));
    }
    return rows;
  }

  /// Finviz mixes raw numbers, comma-grouped thousands, and suffixed
  /// shorthand ("1.23B", "456.7M") depending on column - handle all three
  /// rather than assume one format. "-" (no data) becomes 0.
  double _parseCompactNumber(String raw) {
    final s = raw.trim().replaceAll(',', '').replaceAll('\$', '');
    if (s.isEmpty || s == '-') return 0.0;
    final suffix = s[s.length - 1].toUpperCase();
    const multipliers = {'K': 1e3, 'M': 1e6, 'B': 1e9, 'T': 1e12};
    final multiplier = multipliers[suffix];
    if (multiplier != null) {
      final value = double.tryParse(s.substring(0, s.length - 1));
      return value != null ? value * multiplier : 0.0;
    }
    return double.tryParse(s) ?? 0.0;
  }

  void close() => _http.close();
}
