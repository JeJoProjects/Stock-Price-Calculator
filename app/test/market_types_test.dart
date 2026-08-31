import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/market/market_types.dart';

void main() {
  test('MarketSnapshot.isValid requires both a quote and candles', () {
    const noQuote = MarketSnapshot(symbol: 'AAPL', timeframe: Timeframe.day1, candles: [
      Candle(time: 0, open: 1, high: 2, low: 0.5, close: 1.5, volume: 100),
    ]);
    expect(noQuote.isValid, false);

    const noCandles = MarketSnapshot(
      symbol: 'AAPL',
      timeframe: Timeframe.day1,
      quote: Quote(current: 1.5),
    );
    expect(noCandles.isValid, false);

    const both = MarketSnapshot(
      symbol: 'AAPL',
      timeframe: Timeframe.day1,
      quote: Quote(current: 1.5),
      candles: [Candle(time: 0, open: 1, high: 2, low: 0.5, close: 1.5, volume: 100)],
    );
    expect(both.isValid, true);
  });

  test('Candle.dateTime converts unix seconds correctly', () {
    final candle = Candle.fromJson({
      'time': 1700000000,
      'open': 1,
      'high': 2,
      'low': 0.5,
      'close': 1.5,
      'volume': 100,
    });
    expect(candle.dateTime, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
  });

  test('Timeframe labels match backend expectations', () {
    expect(Timeframe.day1.label, '1D');
    expect(Timeframe.max.label, 'MAX');
  });
}
