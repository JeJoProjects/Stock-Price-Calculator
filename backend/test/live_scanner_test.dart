import 'package:backend/finviz_client.dart';
import 'package:backend/live_scanner.dart';
import 'package:backend/yahoo_stream.dart';
import 'package:test/test.dart';

FinvizRow _f(String s, {double price = 10, double prevClose = 8, double vol = 1e6, double relVol = 4, double float = 5e6}) =>
    FinvizRow(
      symbol: s,
      company: '$s Inc',
      marketCap: 50e6,
      price: price,
      changePercent: (price - prevClose) / prevClose * 100,
      volume: vol,
      prevClose: prevClose,
      relativeVolume: relVol,
      averageVolume: 250000,
      floatShares: float,
      shortFloatPercent: 25,
    );

void main() {
  late DateTime now;
  late LiveScanner scanner;

  setUp(() {
    now = DateTime.utc(2026, 11, 12, 15, 0);
    scanner = LiveScanner(finviz: FinvizClient(), stream: YahooStream(), clock: () => now);
    scanner.setUniverse({
      'AAA': (_f('AAA'), {'unusualVolume'}),
      'BBB': (_f('BBB', price: 9, prevClose: 10, float: 50e6), {'topGainer'}),
    });
  });

  PriceTick tick(String s, double price, {int volume = 0}) =>
      PriceTick(symbol: s, price: price, time: now, dayVolume: volume, session: MarketSession.regular);

  Map<String, Object?> row(String s) => scanner.rows().firstWhere((r) => r['symbol'] == s);

  test('before any tick rows show Finviz numbers, sorted by change', () {
    final rows = scanner.rows();
    expect(rows.map((r) => r['symbol']), ['AAA', 'BBB']);
    expect(rows.first['changePercent'], 25.0);
    expect(rows.first['live'], isFalse);
    expect(rows.first['flags'], containsAll(['lowFloat', 'highShort', 'unusualVolume']));
    expect(rows.last['flags'], isNot(contains('lowFloat')));
  });

  test('ticks move price, change, relative volume and direction', () {
    final v0 = scanner.version;
    scanner.applyTick(tick('AAA', 12, volume: 2000000));
    expect(scanner.version, greaterThan(v0));
    final r = row('AAA');
    expect(r['price'], 12.0);
    expect(r['changePercent'], 50.0); // vs Finviz previous close 8
    expect(r['relVolume'], 8.0); // 4x scaled by 2M/1M live volume
    expect(r['volume'], 2000000.0);
    expect(r['dir'], 1);
    expect(r['live'], isTrue);
    expect(r['session'], 'regular');
  });

  test('1- and 5-minute change, new-high flag and momentum', () {
    scanner.applyTick(tick('AAA', 10));
    now = now.add(const Duration(minutes: 4));
    scanner.applyTick(tick('AAA', 10.2));
    now = now.add(const Duration(seconds: 50));
    scanner.applyTick(tick('AAA', 10.5));
    final r = row('AAA');
    expect(r['change5m'], 5.0);
    expect(r['change1m'], closeTo(2.94, 0.01));
    expect(r['flags'], contains('newHigh'));
    expect(r['momentum'] as int, greaterThan(70));
  });

  test('unknown symbols and bad prices are ignored', () {
    final v0 = scanner.version;
    scanner.applyTick(tick('ZZZ', 5));
    scanner.applyTick(tick('AAA', 0));
    expect(scanner.version, v0);
  });

  test('a universe refresh keeps live state of symbols that stay', () {
    scanner.applyTick(tick('AAA', 12));
    scanner.setUniverse({'AAA': (_f('AAA'), {'topGainer'})});
    expect(scanner.rows().single['price'], 12.0);
    expect(scanner.rows().single['flags'], contains('topGainer'));
  });

  test('momentum score is bounded and ignores falling prices', () {
    expect(momentumScore(change5m: 50, change1m: 50, relVolume: 100, changePercent: 500), 100);
    expect(momentumScore(change5m: -5, change1m: -2, relVolume: 0.5, changePercent: -10), 0);
    expect(momentumScore(change5m: 2.5, change1m: 0, relVolume: 1, changePercent: 0), 20);
  });

  test('snapshot carries stream and universe status', () {
    final s = scanner.snapshot();
    expect(s['type'], 'snapshot');
    expect((s['rows'] as List).length, 2);
    expect((s['stream'] as Map)['connected'], isFalse);
    expect(s['universeUpdated'], isNotNull);
  });
}
