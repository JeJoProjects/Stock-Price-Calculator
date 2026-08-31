import 'package:backend/screener_isolate.dart';
import 'package:backend/ticker_universe.dart';
import 'package:test/test.dart';

void main() {
  test('ScreenerIsolateRunner spawns, polls, and reports back over the SendPort', () async {
    // A fake (invalid) key so client.hasApiKey is true and the isolate
    // actually runs its poll loop instead of the intentional early-return
    // no-op for a missing key. A 2-symbol override (instead of the full
    // ~200-ticker universe) keeps this fast regardless of Finnhub's real
    // response time - this test is about the isolate boundary (spawn, run,
    // send results back), not real data.
    final runner = ScreenerIsolateRunner();
    await runner.start(
      apiKey: 'invalid-test-key',
      pollInterval: const Duration(seconds: 30),
      requestSpacing: const Duration(milliseconds: 1),
      tickerUniverseOverride: const [
        TickerInfo(symbol: 'AAPL', name: 'Apple Inc', exchange: 'NASDAQ'),
        TickerInfo(symbol: 'MSFT', name: 'Microsoft Corp', exchange: 'NASDAQ'),
      ],
    );

    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (runner.lastUpdated == null && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    expect(runner.lastUpdated, isNotNull);
    // Invalid key -> every quote fetch fails -> zero rows, but the isolate
    // completed a full cycle and reported back successfully.
    expect(runner.latest, isEmpty);

    runner.dispose();
  }, timeout: const Timeout(Duration(seconds: 35)));
}
