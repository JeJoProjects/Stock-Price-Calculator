import 'package:backend/screener_criteria.dart';
import 'package:test/test.dart';

ScreenerRow _row({
  String symbol = 'TEST',
  double marketCap = 100e6,
  double changePercent = 15.0,
}) =>
    ScreenerRow(
      symbol: symbol,
      name: '$symbol Inc',
      exchange: 'NASDAQ',
      marketCap: marketCap,
      price: 5.0,
      changePercent: changePercent,
      volume: 1000000,
    );

void main() {
  test('excludes market cap above threshold', () {
    const criteria = ScreenerCriteria(maxMarketCap: 500e6, minChangePercent: 10.0);
    expect(criteria.matches(_row(marketCap: 600e6)), false);
    expect(criteria.matches(_row(marketCap: 400e6)), true);
  });

  test('excludes zero or unknown market cap', () {
    const criteria = ScreenerCriteria();
    expect(criteria.matches(_row(marketCap: 0)), false);
  });

  test('excludes change percent below minimum', () {
    const criteria = ScreenerCriteria(minChangePercent: 10.0);
    expect(criteria.matches(_row(changePercent: 5.0)), false);
    expect(criteria.matches(_row(changePercent: -5.0)), false);
    expect(criteria.matches(_row(changePercent: -15.0)), true);
  });

  test('respects an upper change-percent bound when set', () {
    const criteria = ScreenerCriteria(minChangePercent: 10.0, maxChangePercent: 20.0);
    expect(criteria.matches(_row(changePercent: 15.0)), true);
    expect(criteria.matches(_row(changePercent: 25.0)), false);
  });

  test('applyScreener sorts by absolute change percent descending and limits results', () {
    final rows = [
      _row(symbol: 'A', changePercent: 12.0),
      _row(symbol: 'B', changePercent: -30.0),
      _row(symbol: 'C', changePercent: 20.0),
      _row(symbol: 'D', marketCap: 600e6, changePercent: 50.0), // filtered out: market cap
    ];
    final result = applyScreener(rows, const ScreenerCriteria(), limit: 2);
    expect(result.map((r) => r.symbol).toList(), ['B', 'C']);
  });
}
