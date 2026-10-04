import 'package:backend/alpha_vantage_client.dart';
import 'package:backend/market_types.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _intradaySampleJson = '''
{
  "Meta Data": {
    "1. Information": "Intraday (5min) open, high, low, close prices and volume",
    "2. Symbol": "IBM",
    "3. Last Refreshed": "2024-01-15 19:55:00",
    "4. Interval": "5min",
    "5. Output Size": "Full size",
    "6. Time Zone": "US/Eastern"
  },
  "Time Series (5min)": {
    "2024-01-15 19:55:00": {
      "1. open": "123.60",
      "2. high": "123.70",
      "3. low": "123.55",
      "4. close": "123.65",
      "5. volume": "500"
    },
    "2024-01-15 09:30:00": {
      "1. open": "123.45",
      "2. high": "123.67",
      "3. low": "123.20",
      "4. close": "123.50",
      "5. volume": "1000000"
    },
    "2024-01-14 15:55:00": {
      "1. open": "122.00",
      "2. high": "122.50",
      "3. low": "121.80",
      "4. close": "122.30",
      "5. volume": "800000"
    }
  }
}
''';

const _dailySampleJson = '''
{
  "Meta Data": {
    "1. Information": "Daily Prices (open, high, low, close) and Volumes",
    "2. Symbol": "IBM",
    "3. Last Refreshed": "2024-01-15",
    "4. Output Size": "Compact",
    "5. Time Zone": "US/Eastern"
  },
  "Time Series (Daily)": {
    "2024-01-15": {
      "1. open": "123.45",
      "2. high": "123.67",
      "3. low": "123.20",
      "4. close": "123.50",
      "5. volume": "1000000"
    }
  }
}
''';

const _rateLimitJson = '''
{
  "Information": "Thank you for using Alpha Vantage! Our standard API rate limit is 25 requests per day."
}
''';

const _errorJson = '''
{
  "Error Message": "Invalid API call. Please retry or visit the documentation."
}
''';

void main() {
  test('parses intraday series, sorts ascending, and keeps only the latest trading day for day1', () async {
    final client = AlphaVantageClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async {
        expect(request.url.host, 'www.alphavantage.co');
        expect(request.url.queryParameters['function'], 'TIME_SERIES_INTRADAY');
        expect(request.url.queryParameters['symbol'], 'IBM');
        expect(request.url.queryParameters['interval'], '5min');
        expect(request.url.queryParameters['extended_hours'], 'true');
        expect(request.url.queryParameters['apikey'], 'test-key');
        return http.Response(_intradaySampleJson, 200);
      }),
    );

    final result = await client.fetchCandles('IBM', Timeframe.day1);

    expect(result.isOk, isTrue);
    final candles = result.value!;
    // Only the two 2024-01-15 bars should survive the day1 trim, and in
    // ascending time order.
    expect(candles, hasLength(2));
    expect(candles[0].open, 123.45);
    expect(candles[1].open, 123.60);
    expect(candles[0].time, lessThan(candles[1].time));
  });

  test('parses a daily series for month6/year1/max', () async {
    final client = AlphaVantageClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async {
        expect(request.url.queryParameters['function'], 'TIME_SERIES_DAILY');
        expect(request.url.queryParameters['outputsize'], 'compact');
        return http.Response(_dailySampleJson, 200);
      }),
    );

    final result = await client.fetchCandles('IBM', Timeframe.year1);

    expect(result.isOk, isTrue);
    expect(result.value, hasLength(1));
    expect(result.value!.first.close, 123.50);
  });

  test('maps a quota-exceeded response to a rate-limited error, not a crash', () async {
    final client = AlphaVantageClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async => http.Response(_rateLimitJson, 200)),
    );

    final result = await client.fetchCandles('IBM', Timeframe.day1);

    expect(result.isOk, isFalse);
    expect(result.rateLimited, isTrue);
    expect(result.error, contains('try again later'));
  });

  test('surfaces Alpha Vantage\'s own error message for a bad request', () async {
    final client = AlphaVantageClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async => http.Response(_errorJson, 200)),
    );

    final result = await client.fetchCandles('NOTASYMBOL', Timeframe.day1);

    expect(result.isOk, isFalse);
    expect(result.rateLimited, isFalse);
    expect(result.error, contains('Invalid API call'));
  });

  test('returns an error without an API key configured, never calling the network', () async {
    final client = AlphaVantageClient(
      apiKey: '',
      httpClient: MockClient((request) async => throw StateError('should not be called')),
    );

    final result = await client.fetchCandles('IBM', Timeframe.day1);

    expect(result.isOk, isFalse);
    expect(result.error, contains('not configured'));
  });
}
