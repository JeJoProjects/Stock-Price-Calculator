import 'dart:convert';

import 'package:backend/finviz_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A synthetic screener page shaped like Finviz's redesigned markup: the
/// table data ships as JSON in an SSR "island" script tag (invented tickers
/// and numbers; the field names match the live v=152 custom view).
String _page(List<Map<String, Object?>> rows, {int total = 2, int firstRow = 1, int pageSize = 20}) {
  final island = jsonEncode({
    'data': {'rows': rows, 'totalCount': total, 'firstRow': firstRow, 'pageSize': pageSize},
  });
  return '<html><body><div id="root"></div>'
      '<script type="application/json" data-ssr-props="nav">{"menu":[]}</script>'
      '<script type="application/json" data-ssr-props="screener">$island</script>'
      '</body></html>';
}

Map<String, Object?> _row(String ticker, {double change = 10, double price = 5}) => {
      'text': {
        'ticker': ticker,
        'company': '$ticker Corp',
        'sector': 'Technology',
        'industry': 'Software',
        'country': 'USA',
      },
      'numbers': {
        'marketCap': 120.5,
        'price': price,
        'change': change,
        'volume': 2500000,
        'prevClose': 4.5,
        'open': 4.8,
        'gap': 6.67,
        'changeopen': 4.17,
        'relativeVolume': 7.2,
        'averageVolume': 350000,
        'sharesFloat': 8.4,
        'shortInterestShare': 21.5,
        'rsi': 71.3,
      },
    };

void main() {
  test('parses rows and paging info from the JSON island', () {
    final page = FinvizClient.parsePage(_page([_row('ABCD'), _row('WXYZ', change: 3)], total: 57));
    expect(page.totalCount, 57);
    expect(page.pageSize, 20);
    expect(page.rows.map((r) => r.symbol), ['ABCD', 'WXYZ']);
    final r = page.rows.first;
    expect(r.company, 'ABCD Corp');
    expect(r.sector, 'Technology');
    expect(r.marketCap, closeTo(120.5e6, 1));
    expect(r.price, 5);
    expect(r.changePercent, 10);
    expect(r.prevClose, 4.5);
    expect(r.gapPercent, 6.67);
    expect(r.relativeVolume, 7.2);
    expect(r.averageVolume, 350000);
    expect(r.floatShares, closeTo(8.4e6, 1));
    expect(r.shortFloatPercent, 21.5);
  });

  test('skips rows without a ticker and tolerates missing numbers', () {
    final page = FinvizClient.parsePage(_page([
      {'text': {'ticker': ''}, 'numbers': {}},
      {'text': {'ticker': 'ONLY'}},
    ]));
    expect(page.rows.single.symbol, 'ONLY');
    expect(page.rows.single.floatShares, 0);
  });

  test('a page without a data island is reported clearly', () {
    expect(
      () => FinvizClient.parsePage('<html><body>Access denied</body></html>'),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('not recognized'))),
    );
  });

  test('fetchAll walks pages with r= and stops at maxPages', () async {
    final requested = <String?>[];
    final client = FinvizClient(
      pageDelay: Duration.zero,
      httpClient: MockClient((req) async {
        final r = req.url.queryParameters['r'];
        requested.add(r);
        expect(req.url.queryParameters['v'], '152');
        expect(req.url.queryParameters['s'], 'ta_unusualvolume');
        final first = int.parse(r ?? '1');
        return http.Response(_page([_row('S$first')], total: 95, firstRow: first), 200);
      }),
    );
    final rows = await client.fetchAll(maxPages: 3);
    expect(requested, [null, '21', '41']);
    expect(rows.map((r) => r.symbol), ['S1', 'S21', 'S41']);
  });

  test('HTTP 429 becomes FinvizRateLimited', () async {
    final client = FinvizClient(httpClient: MockClient((_) async => http.Response('slow down', 429)));
    expect(client.fetchPage(), throwsA(isA<FinvizRateLimited>()));
  });
}
