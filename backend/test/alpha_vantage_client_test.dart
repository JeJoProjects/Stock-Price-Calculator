import 'package:backend/alpha_vantage_client.dart';
import 'package:backend/market_types.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// A trimmed-but-real-shaped TIME_SERIES_DAILY response. Every Timeframe
// uses this same endpoint now - see alpha_vantage_client.dart's doc
// comment for why TIME_SERIES_INTRADAY (used in an earlier version of
// this client) turned out to be premium-only on current free keys,
// despite what Alpha Vantage's public docs say.
const _dailySampleJson = '''
{
  "Meta Data": {
    "1. Information": "Daily Prices (open, high, low, close) and Volumes",
    "2. Symbol": "IBM",
    "3. Last Refreshed": "2024-01-10",
    "4. Output Size": "Compact",
    "5. Time Zone": "US/Eastern"
  },
  "Time Series (Daily)": {
    "2024-01-10": {"1. open": "110", "2. high": "111", "3. low": "109", "4. close": "110.5", "5. volume": "10"},
    "2024-01-09": {"1. open": "109", "2. high": "110", "3. low": "108", "4. close": "109.5", "5. volume": "9"},
    "2024-01-08": {"1. open": "108", "2. high": "109", "3. low": "107", "4. close": "108.5", "5. volume": "8"},
    "2024-01-05": {"1. open": "107", "2. high": "108", "3. low": "106", "4. close": "107.5", "5. volume": "7"},
    "2024-01-04": {"1. open": "106", "2. high": "107", "3. low": "105", "4. close": "106.5", "5. volume": "6"},
    "2024-01-03": {"1. open": "105", "2. high": "106", "3. low": "104", "4. close": "105.5", "5. volume": "5"},
    "2024-01-02": {"1. open": "104", "2. high": "105", "3. low": "103", "4. close": "104.5", "5. volume": "4"}
  }
}
''';

const _rateLimitJson = '''
{
  "Information": "Thank you for using Alpha Vantage! Our standard API rate limit is 25 requests per day."
}
''';

const _premiumEndpointJson = '''
{
  "Information": "Thank you for using Alpha Vantage! This is a premium endpoint. You may subscribe to any of the premium plans at https://www.alphavantage.co/premium/ to instantly unlock all premium endpoints"
}
''';

const _errorJson = '''
{
  "Error Message": "Invalid API call. Please retry or visit the documentation."
}
''';

void main() {
  test('always requests TIME_SERIES_DAILY/compact, regardless of timeframe', () async {
    for (final tf in Timeframe.values) {
      final client = AlphaVantageClient(
        apiKey: 'test-key',
        httpClient: MockClient((request) async {
          expect(request.url.host, 'www.alphavantage.co');
          expect(request.url.queryParameters['function'], 'TIME_SERIES_DAILY');
          expect(request.url.queryParameters['outputsize'], 'compact');
          expect(request.url.queryParameters['symbol'], 'IBM');
          expect(request.url.queryParameters['apikey'], 'test-key');
          return http.Response(_dailySampleJson, 200);
        }),
      );
      final result = await client.fetchCandles('IBM', tf);
      expect(result.isOk, isTrue, reason: 'failed for $tf');
    }
  });

  test('parses daily series sorted ascending by time', () async {
    final client = AlphaVantageClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async => http.Response(_dailySampleJson, 200)),
    );

    final result = await client.fetchCandles('IBM', Timeframe.max);

    expect(result.isOk, isTrue);
    final candles = result.value!;
    expect(candles, hasLength(7));
    expect(candles.first.open, 104);
    expect(candles.last.open, 110);
    for (var i = 1; i < candles.length; i++) {
      expect(candles[i].time, greaterThan(candles[i - 1].time));
    }
  });

  test('day1 keeps only the single most recent daily bar', () async {
    final client = AlphaVantageClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async => http.Response(_dailySampleJson, 200)),
    );

    final result = await client.fetchCandles('IBM', Timeframe.day1);

    expect(result.isOk, isTrue);
    expect(result.value, hasLength(1));
    expect(result.value!.single.open, 110);
  });

  test('week1 keeps the last 5 trading days', () async {
    final client = AlphaVantageClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async => http.Response(_dailySampleJson, 200)),
    );

    final result = await client.fetchCandles('IBM', Timeframe.week1);

    expect(result.isOk, isTrue);
    expect(result.value, hasLength(5));
    expect(result.value!.first.open, 106); // 2024-01-04 onward (last 5 of 7 bars)
  });

  test('month6/year1/max all return everything compact gave back (same ~100-day cap)', () async {
    final client = AlphaVantageClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async => http.Response(_dailySampleJson, 200)),
    );

    for (final tf in [Timeframe.month6, Timeframe.year1, Timeframe.max]) {
      final result = await client.fetchCandles('IBM', tf);
      expect(result.value, hasLength(7), reason: 'failed for $tf');
    }
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

  test('maps a premium-endpoint response to a rate-limited error too (not a crash)', () async {
    final client = AlphaVantageClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async => http.Response(_premiumEndpointJson, 200)),
    );

    final result = await client.fetchCandles('IBM', Timeframe.day1);

    expect(result.isOk, isFalse);
    expect(result.rateLimited, isTrue);
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
