import 'package:backend/yahoo_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// A trimmed fragment of the real response shape returned by
// https://query1.finance.yahoo.com/v1/finance/screener/predefined/saved
// ?scrIds=day_gainers (verified against a live fetch while building this).
// Includes one quote with plain numeric fields and one with the {raw, fmt}
// wrapper shape Yahoo sometimes uses, to exercise both code paths.
const _sampleJson = '''
{
  "finance": {
    "result": [
      {
        "id": "day_gainers",
        "quotes": [
          {
            "symbol": "BLTE",
            "longName": "Belite Bio, Inc.",
            "fullExchangeName": "NasdaqGS",
            "regularMarketPrice": 193.61,
            "regularMarketChangePercent": 13.16,
            "regularMarketVolume": 1234567,
            "marketCap": 2500000000
          },
          {
            "symbol": "AEHR",
            "shortName": "Aehr Test Systems",
            "exchange": "NGM",
            "regularMarketPrice": {"raw": 21.4, "fmt": "21.40"},
            "regularMarketChangePercent": {"raw": 13.10, "fmt": "13.10%"},
            "regularMarketVolume": {"raw": 9876543, "fmt": "9.88M"},
            "marketCap": {"raw": 987654321, "fmt": "987.65M"}
          }
        ]
      }
    ]
  }
}
''';

void main() {
  test('parses real Yahoo screener JSON, including plain and {raw,fmt} numeric shapes', () async {
    final client = YahooClient(
      httpClient: MockClient((request) async {
        expect(request.url.host, 'query1.finance.yahoo.com');
        expect(request.url.path, '/v1/finance/screener/predefined/saved');
        expect(request.url.queryParameters['scrIds'], 'day_gainers');
        expect(request.headers['User-Agent'], isNotEmpty);
        return http.Response(_sampleJson, 200);
      }),
    );

    final rows = await client.fetchTopGainers();

    expect(rows, hasLength(2));
    expect(rows[0].symbol, 'BLTE');
    expect(rows[0].company, 'Belite Bio, Inc.');
    expect(rows[0].exchange, 'NasdaqGS');
    expect(rows[0].price, 193.61);
    expect(rows[0].changePercent, closeTo(13.16, 0.001));
    expect(rows[0].volume, 1234567);
    expect(rows[0].marketCap, 2500000000);

    expect(rows[1].symbol, 'AEHR');
    expect(rows[1].company, 'Aehr Test Systems');
    expect(rows[1].price, 21.4);
    expect(rows[1].changePercent, closeTo(13.10, 0.001));
    expect(rows[1].volume, 9876543);
    expect(rows[1].marketCap, closeTo(987654321, 1));
  });

  test('throws a clear error on a non-200 response', () async {
    final client = YahooClient(
      httpClient: MockClient((request) async => http.Response('blocked', 403)),
    );
    expect(() => client.fetchTopGainers(), throwsStateError);
  });

  test('throws when the response is not JSON (blocked or endpoint changed)', () async {
    final client = YahooClient(
      httpClient: MockClient((request) async => http.Response('<html>not json</html>', 200)),
    );
    expect(() => client.fetchTopGainers(), throwsStateError);
  });

  test('throws when the JSON structure is unrecognized', () async {
    final client = YahooClient(
      httpClient: MockClient((request) async => http.Response('{"finance": {"result": []}}', 200)),
    );
    expect(() => client.fetchTopGainers(), throwsStateError);
  });
}
