import 'package:backend/finviz_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// A trimmed two-row fragment of the real markup returned by
// https://finviz.com/screener?v=111&s=ta_unusualvolume&o=-change (verified
// against a live fetch while building this), including the ticker cell's
// logo-fallback avatar span that pollutes plain .text extraction.
const _sampleHtml = '''
<table class="styled-table-new is-rounded is-tabular-nums w-full screener_table">
<thead>
<tr><th>No.</th><th>Ticker</th><th>Company</th><th>Sector</th><th>Industry</th>
<th>Country</th><th>Market Cap</th><th>P/E</th><th>Price</th><th>Change %</th><th>Volume</th></tr>
</thead>
<tr class="styled-row is-bordered is-rounded group is-hoverable is-striped has-color-text" valign="top">
<td height="10" align="right"><a href="stock?t=TRBG">1</a></td>
<td height="10" align="left"><span class="flex items-center gap-1 pl-0.5"><a class="company-ticker" href="stock?t=TRBG"><span>T</span></a><a href="stock?t=TRBG" class="tab-link">TRBG</a></span></td>
<td height="10" align="left"><a href="stock?t=TRBG">Turbogen Ltd</a></td>
<td height="10" align="left"><a href="stock?t=TRBG">Industrials</a></td>
<td height="10" align="left"><a href="stock?t=TRBG">Specialty Industrial Machinery</a></td>
<td height="10" align="left"><a href="stock?t=TRBG">Israel</a></td>
<td height="10" align="right"><a href="stock?t=TRBG">-</a></td>
<td height="10" align="right"><a href="stock?t=TRBG">-</a></td>
<td height="10" align="right"><a href="stock?t=TRBG"><span class="color-text is-positive">11.84</span></a></td>
<td height="10" align="right"><a href="stock?t=TRBG"><span class="color-text is-positive">89.14%</span></a></td>
<td height="10" align="right"><a href="stock?t=TRBG">837,334</a></td>
</tr>
<tr class="styled-row is-bordered is-rounded group is-hoverable is-striped has-color-text" valign="top">
<td height="10" align="right"><a href="stock?t=CHPT">2</a></td>
<td height="10" align="left"><span class="flex items-center gap-1 pl-0.5"><a class="company-ticker" href="stock?t=CHPT"><span>C</span></a><a href="stock?t=CHPT" class="tab-link">CHPT</a></span></td>
<td height="10" align="left"><a href="stock?t=CHPT">ChargePoint Holdings Inc</a></td>
<td height="10" align="left"><a href="stock?t=CHPT">Consumer Cyclical</a></td>
<td height="10" align="left"><a href="stock?t=CHPT">Specialty Retail</a></td>
<td height="10" align="left"><a href="stock?t=CHPT">USA</a></td>
<td height="10" align="right"><a href="stock?t=CHPT">235.15M</a></td>
<td height="10" align="right"><a href="stock?t=CHPT">-</a></td>
<td height="10" align="right"><a href="stock?t=CHPT"><span class="color-text is-positive">9.08</span></a></td>
<td height="10" align="right"><a href="stock?t=CHPT"><span class="color-text is-positive">74.95%</span></a></td>
<td height="10" align="right"><a href="stock?t=CHPT">43,484,107</a></td>
</tr>
</table>
''';

void main() {
  test('parses real Finviz screener markup, including the ticker avatar-span pollution', () async {
    final client = FinvizClient(
      httpClient: MockClient((request) async {
        expect(request.url.host, 'finviz.com');
        expect(request.url.path, '/screener');
        expect(request.url.queryParameters['s'], 'ta_unusualvolume');
        expect(request.url.queryParameters['o'], '-change');
        expect(request.headers['User-Agent'], isNotEmpty);
        return http.Response(_sampleHtml, 200);
      }),
    );

    final rows = await client.fetchUnusualVolumeMovers();

    expect(rows, hasLength(2));
    expect(rows[0].symbol, 'TRBG'); // not "TTRBG" - avatar-span text excluded
    expect(rows[0].company, 'Turbogen Ltd');
    expect(rows[0].sector, 'Industrials');
    expect(rows[0].marketCap, 0.0); // "-" -> no data
    expect(rows[0].price, 11.84);
    expect(rows[0].changePercent, closeTo(89.14, 0.001));
    expect(rows[0].volume, 837334);

    expect(rows[1].symbol, 'CHPT');
    expect(rows[1].marketCap, closeTo(235.15e6, 1));
    expect(rows[1].volume, 43484107);
  });

  test('throws a clear error on a non-200 response', () async {
    final client = FinvizClient(
      httpClient: MockClient((request) async => http.Response('blocked', 403)),
    );
    expect(() => client.fetchUnusualVolumeMovers(), throwsStateError);
  });

  test('throws when the page structure is unrecognized (blocked or markup changed)', () async {
    final client = FinvizClient(
      httpClient: MockClient((request) async => http.Response('<html>not the screener</html>', 200)),
    );
    expect(() => client.fetchUnusualVolumeMovers(), throwsStateError);
  });
}
