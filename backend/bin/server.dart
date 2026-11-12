import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:backend/alpha_vantage_client.dart';
import 'package:backend/candle_cache.dart';
import 'package:backend/finnhub_client.dart';
import 'package:backend/finviz_client.dart';
import 'package:backend/live_scanner.dart';
import 'package:backend/market_types.dart';
import 'package:backend/screener_row.dart';
import 'package:backend/symbol_search.dart';
import 'package:backend/yahoo_client.dart';
import 'package:backend/yahoo_screener_service.dart';
import 'package:backend/yahoo_stream.dart';

Response _json(Object body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json', 'access-control-allow-origin': '*'},
    );

void main(List<String> args) async {
  final apiKey = Platform.environment['FINNHUB_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    stderr.writeln(
        'WARNING: FINNHUB_API_KEY is not set. Quote/profile/candle/screener endpoints will return errors until it is configured.');
  }

  final client = FinnhubClient(apiKey: apiKey);
  final symbolSearch = SymbolSearchClient();

  // Finnhub's /stock/candle moved behind a paid plan on newer accounts
  // (see finnhub_client.dart's KNOWN RISK note) - candle/OHLC data comes
  // from Alpha Vantage's free tier instead (see alpha_vantage_client.dart).
  // Finnhub above still handles quote/profile, which remain free.
  final alphaVantageKey = Platform.environment['ALPHA_VANTAGE_API_KEY'] ?? '';
  if (alphaVantageKey.isEmpty) {
    stderr.writeln(
        'WARNING: ALPHA_VANTAGE_API_KEY is not set. The chart\'s candle data will be unavailable until it is configured.');
  }
  final alphaVantageClient = AlphaVantageClient(apiKey: alphaVantageKey);
  // Alpha Vantage's free tier is roughly 25 requests/day - this disk-backed
  // cache (survives app restarts, unlike an in-memory map - see
  // candle_cache.dart) is what makes that quota usable across a normal day
  // instead of being exhausted after a handful of chart loads.
  final cacheTtlSeconds = int.tryParse(Platform.environment['ALPHA_VANTAGE_CACHE_SECONDS'] ?? '') ?? 3600;
  final candleCache = CandleCache(
    path: '${File(Platform.resolvedExecutable).parent.path}/alpha_vantage_cache.json',
    ttl: Duration(seconds: cacheTtlSeconds),
  );

  // The screener panel is fed straight from Finviz's and Yahoo's free
  // screener pages/APIs (finviz_client.dart, yahoo_client.dart) - no account
  // or key needed, unlike Finnhub above.
  final finvizClient = FinvizClient();
  final yahooClient = YahooClient();
  // How often the backend re-fetches each source - the app's Settings >
  // Display "Screener Refresh" control only governs how often the app
  // re-fetches these already-computed, cached results, not how often the
  // backend talks to Finviz/Yahoo.
  final pollSeconds = int.tryParse(Platform.environment['SCREENER_POLL_SECONDS'] ?? '') ?? 30;

  // Live scanner: Finviz picks the stocks (delayed, so ~once a minute is
  // plenty and avoids getting blocked), Yahoo's stream prices them per trade.
  final universeSeconds = int.tryParse(Platform.environment['SCANNER_UNIVERSE_SECONDS'] ?? '') ?? 60;
  final scanner = LiveScanner(
    finviz: finvizClient,
    stream: YahooStream(),
    refreshInterval: Duration(seconds: universeSeconds.clamp(20, 3600)),
  );
  scanner.start();

  final yahooScreener = YahooScreenerService(
    client: yahooClient,
    pollInterval: Duration(seconds: pollSeconds),
  );
  yahooScreener.start();

  final router = Router()
    ..get('/health', (Request req) => _json({'status': 'ok'}))
    ..get('/quote/<symbol>', (Request req, String symbol) async {
      final result = await client.fetchQuote(symbol);
      if (!result.isOk) return _json({'error': result.error}, status: 502);
      return _json(result.value!.toJson());
    })
    ..get('/profile/<symbol>', (Request req, String symbol) async {
      final result = await client.fetchProfile(symbol);
      if (!result.isOk) return _json({'error': result.error}, status: 502);
      return _json(result.value!.toJson());
    })
    ..get('/candles/<symbol>', (Request req, String symbol) async {
      final label = req.url.queryParameters['timeframe'] ?? '1D';
      final timeframe = TimeframeInfo.fromLabel(label);

      final cached = await candleCache.get(symbol, timeframe);
      if (cached != null) {
        return _json({'candles': cached.map((c) => c.toJson()).toList(), 'cached': true});
      }

      final result = await alphaVantageClient.fetchCandles(symbol, timeframe);
      if (!result.isOk) return _json({'error': result.error}, status: 502);
      await candleCache.set(symbol, timeframe, result.value!);
      return _json({'candles': result.value!.map((c) => c.toJson()).toList()});
    })
    ..get('/search', (Request req) async {
      final q = req.url.queryParameters['q'] ?? '';
      if (q.trim().length < 2) return _json({'results': []});
      final maxResults = int.tryParse(req.url.queryParameters['max'] ?? '') ?? 12;
      final results = await symbolSearch.search(q, maxResults: maxResults);
      return _json({'results': results.map((r) => r.toJson()).toList()});
    })
    ..get('/scanner', (Request req) => _json(scanner.snapshot()))
    ..get('/live', _liveSocket(scanner))
    ..get('/screener/finviz', (Request req) {
      return _json({
        'rows': _finvizRail(scanner).map((r) => r.toJson()).toList(),
        'lastUpdated': scanner.universeUpdated?.toIso8601String(),
        'error': scanner.universeError,
      });
    })
    ..get('/screener/yahoo', (Request req) {
      return _json({
        'rows': yahooScreener.latest.map((r) => r.toJson()).toList(),
        'lastUpdated': yahooScreener.lastUpdated?.toIso8601String(),
        'error': yahooScreener.lastError,
      });
    })
    ..get('/screener/combined', (Request req) {
      final finvizBySymbol = {for (final r in _finvizRail(scanner, limit: 400)) r.symbol: r};
      final yahooBySymbol = {for (final r in yahooScreener.latest) r.symbol: r};
      final commonSymbols = finvizBySymbol.keys.toSet().intersection(yahooBySymbol.keys.toSet());
      final rows = commonSymbols.map((symbol) {
        final f = finvizBySymbol[symbol]!;
        final y = yahooBySymbol[symbol]!;
        // Finviz's row is the richer one (it carries sector) so it's the
        // base; fall back to Yahoo's fields only where Finviz left a gap.
        return ScreenerRow(
          symbol: symbol,
          name: f.name.isNotEmpty ? f.name : y.name,
          exchange: f.exchange.isNotEmpty ? f.exchange : y.exchange,
          sector: f.sector,
          marketCap: f.marketCap > 0 ? f.marketCap : y.marketCap,
          price: f.price,
          changePercent: f.changePercent,
          volume: f.volume,
          source: 'both',
        );
      }).toList()
        ..sort((a, b) => b.changePercent.compareTo(a.changePercent));

      final finvizUpdated = scanner.universeUpdated;
      final yahooUpdated = yahooScreener.lastUpdated;
      DateTime? lastUpdated;
      if (finvizUpdated != null && yahooUpdated != null) {
        lastUpdated = finvizUpdated.isBefore(yahooUpdated) ? finvizUpdated : yahooUpdated;
      } else {
        lastUpdated = finvizUpdated ?? yahooUpdated;
      }

      return _json({
        'rows': rows.map((r) => r.toJson()).toList(),
        'lastUpdated': lastUpdated?.toIso8601String(),
        'error': scanner.universeError ?? yahooScreener.lastError,
      });
    });

  // No per-request logging: the app polls a few endpoints and the scanner
  // socket is long-lived, so request logs would only be noise.
  final handler = const Pipeline().addHandler(router.call);

  final port = int.parse(Platform.environment['PORT'] ?? '8090');
  final server = await serve(handler, InternetAddress.anyIPv4, port);
  print('StockCalc backend listening on port ${server.port}');
}

/// The screener rail's "Finviz" list, now fed live from the scanner: the
/// unusual-volume stocks, top movers first.
List<ScreenerRow> _finvizRail(LiveScanner scanner, {int limit = 20}) => scanner
    .rows()
    .where((r) => (r['flags'] as List).contains('unusualVolume'))
    .take(limit)
    .map((r) => ScreenerRow(
          symbol: r['symbol'] as String,
          name: r['name'] as String,
          sector: r['sector'] as String,
          marketCap: (r['marketCap'] as num).toDouble(),
          price: (r['price'] as num).toDouble(),
          changePercent: (r['changePercent'] as num).toDouble(),
          volume: (r['volume'] as num).toDouble(),
          source: 'finviz',
        ))
    .toList();

/// Pushes scanner snapshots to a client: one immediately, then at most
/// every [interval] while something changed, plus a heartbeat so the app can
/// tell a quiet market from a dead connection.
Handler _liveSocket(LiveScanner scanner, {Duration interval = const Duration(milliseconds: 350)}) =>
    webSocketHandler((WebSocketChannel ws, String? _) {
      var sentVersion = -1;
      var lastSend = DateTime.fromMillisecondsSinceEpoch(0);
      void send() {
        sentVersion = scanner.version;
        lastSend = DateTime.now();
        ws.sink.add(jsonEncode(scanner.snapshot()));
      }

      send();
      final timer = Timer.periodic(interval, (_) {
        if (scanner.version != sentVersion || DateTime.now().difference(lastSend) > const Duration(seconds: 5)) {
          send();
        }
      });
      ws.stream.listen((_) {}, onDone: timer.cancel, onError: (Object _) => timer.cancel());
    });
