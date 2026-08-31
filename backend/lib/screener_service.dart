/// Background polling service: the one process that talks to Finnhub on
/// behalf of every client. Polls the bundled ticker universe on an interval,
/// filters/sorts with screener_criteria.dart, and caches the result for
/// instant serving. This is the fix for the old app's per-user-API-key
/// design — one key, one poller, many clients.
library;

import 'dart:async';
import 'finnhub_client.dart';
import 'screener_criteria.dart';
import 'ticker_universe.dart';

class ScreenerService {
  final FinnhubClient client;
  final ScreenerCriteria criteria;
  final Duration pollInterval;
  final Duration requestSpacing;

  List<ScreenerRow> _latest = [];
  DateTime? _lastUpdated;
  String? _lastError;
  bool _polling = false;
  Timer? _timer;

  final Map<String, double> _marketCapCache = {};
  final Map<String, String> _nameCache = {};
  final Map<String, String> _exchangeCache = {};

  /// Invoked after every poll cycle (success or failure). This is how the
  /// isolate entry point (screener_isolate.dart) forwards results back to
  /// the main isolate without this class needing to know isolates exist.
  final void Function(List<ScreenerRow> rows, DateTime updatedAt, String? error)? onUpdate;

  /// Overrides the bundled ticker universe - used by tests to poll a
  /// handful of symbols instead of the full ~200-ticker list, so a test
  /// doesn't need to wait out a real full sweep to observe one poll cycle.
  final List<TickerInfo>? tickerUniverseOverride;

  ScreenerService({
    required this.client,
    this.criteria = const ScreenerCriteria(),
    this.pollInterval = const Duration(minutes: 5),
    this.requestSpacing = const Duration(milliseconds: 1100),
    this.onUpdate,
    this.tickerUniverseOverride,
  });

  List<ScreenerRow> get latest => _latest;
  DateTime? get lastUpdated => _lastUpdated;
  String? get lastError => _lastError;
  bool get isPolling => _polling;

  void start() {
    _pollOnce();
    _timer = Timer.periodic(pollInterval, (_) => _pollOnce());
  }

  void stop() => _timer?.cancel();

  Future<void> _pollOnce() async {
    if (_polling || !client.hasApiKey) return;
    _polling = true;
    try {
      final universe = tickerUniverseOverride ?? loadTickerUniverse();
      final rows = <ScreenerRow>[];

      for (final ticker in universe) {
        // One request in flight at a time, spaced out, to stay well under
        // Finnhub's free-tier rate limit across the whole universe.
        await Future.delayed(requestSpacing);

        final quoteResult = await client.fetchQuote(ticker.symbol);
        if (!quoteResult.isOk) continue;
        final quote = quoteResult.value!;

        double? marketCap = _marketCapCache[ticker.symbol];
        if (marketCap == null) {
          await Future.delayed(requestSpacing);
          final profileResult = await client.fetchProfile(ticker.symbol);
          if (profileResult.isOk) {
            final profile = profileResult.value!;
            // marketCapitalization from Finnhub is in millions of the
            // listing currency; normalize to raw dollars for the $500M
            // threshold comparison used everywhere else in the app.
            marketCap = profile.marketCap * 1e6;
            _marketCapCache[ticker.symbol] = marketCap;
            _nameCache[ticker.symbol] = profile.name.isNotEmpty ? profile.name : ticker.name;
            _exchangeCache[ticker.symbol] =
                profile.exchange.isNotEmpty ? profile.exchange : ticker.exchange;
          }
        }
        if (marketCap == null) continue;

        rows.add(ScreenerRow(
          symbol: ticker.symbol,
          name: _nameCache[ticker.symbol] ?? ticker.name,
          exchange: _exchangeCache[ticker.symbol] ?? ticker.exchange,
          marketCap: marketCap,
          price: quote.current,
          changePercent: quote.percent,
          volume: 0.0, // Finnhub's /quote endpoint doesn't return volume.
        ));
      }

      _latest = applyScreener(rows, criteria);
      _lastUpdated = DateTime.now();
      _lastError = null;
    } catch (e) {
      _lastError = 'Screener poll failed: $e';
    } finally {
      _polling = false;
      onUpdate?.call(_latest, _lastUpdated ?? DateTime.now(), _lastError);
    }
  }
}
