import 'dart:io';

import 'package:backend/candle_cache.dart';
import 'package:backend/market_types.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String path;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('candle_cache_test');
    path = '${tempDir.path}/cache.json';
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  const sampleCandles = [
    Candle(time: 1000, open: 1, high: 2, low: 0.5, close: 1.5, volume: 100),
  ];

  test('returns null for a key that was never set', () async {
    final cache = CandleCache(path: path, ttl: const Duration(minutes: 5));
    expect(await cache.get('AAPL', Timeframe.day1), isNull);
  });

  test('round-trips a set value within the TTL window', () async {
    final cache = CandleCache(path: path, ttl: const Duration(minutes: 5));
    await cache.set('AAPL', Timeframe.day1, sampleCandles);

    final result = await cache.get('AAPL', Timeframe.day1);
    expect(result, isNotNull);
    expect(result!.single.close, 1.5);
  });

  test('is keyed independently per symbol and timeframe', () async {
    final cache = CandleCache(path: path, ttl: const Duration(minutes: 5));
    await cache.set('AAPL', Timeframe.day1, sampleCandles);

    expect(await cache.get('AAPL', Timeframe.week1), isNull);
    expect(await cache.get('MSFT', Timeframe.day1), isNull);
  });

  test('expires entries past the TTL', () async {
    final cache = CandleCache(path: path, ttl: const Duration(seconds: -1));
    await cache.set('AAPL', Timeframe.day1, sampleCandles);

    expect(await cache.get('AAPL', Timeframe.day1), isNull);
  });

  test('persists across separate CandleCache instances pointed at the same file', () async {
    final first = CandleCache(path: path, ttl: const Duration(minutes: 5));
    await first.set('AAPL', Timeframe.day1, sampleCandles);

    final second = CandleCache(path: path, ttl: const Duration(minutes: 5));
    final result = await second.get('AAPL', Timeframe.day1);
    expect(result, isNotNull);
    expect(result!.single.open, 1);
  });
}
