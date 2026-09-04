import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:backend/finnhub_client.dart';
import 'package:backend/finviz_client.dart';
import 'package:backend/finviz_screener_service.dart';
import 'package:backend/market_types.dart';
import 'package:backend/screener_row.dart';
import 'package:backend/symbol_search.dart';
import 'package:backend/yahoo_client.dart';
import 'package:backend/yahoo_screener_service.dart';

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
  final finvizScreener = FinvizScreenerService(
    client: finvizClient,
    pollInterval: Duration(seconds: pollSeconds),
  );
  finvizScreener.start();
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
      final result = await client.fetchCandles(symbol, timeframe);
      if (!result.isOk) return _json({'error': result.error}, status: 502);
      return _json({'candles': result.value!.map((c) => c.toJson()).toList()});
    })
    ..get('/search', (Request req) async {
      final q = req.url.queryParameters['q'] ?? '';
      if (q.trim().length < 2) return _json({'results': []});
      final maxResults = int.tryParse(req.url.queryParameters['max'] ?? '') ?? 12;
      final results = await symbolSearch.search(q, maxResults: maxResults);
      return _json({'results': results.map((r) => r.toJson()).toList()});
    })
    ..get('/screener/finviz', (Request req) {
      return _json({
        'rows': finvizScreener.latest.map((r) => r.toJson()).toList(),
        'lastUpdated': finvizScreener.lastUpdated?.toIso8601String(),
        'error': finvizScreener.lastError,
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
      final finvizBySymbol = {for (final r in finvizScreener.latest) r.symbol: r};
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

      final finvizUpdated = finvizScreener.lastUpdated;
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
        'error': finvizScreener.lastError ?? yahooScreener.lastError,
      });
    });

  final handler = Pipeline().addMiddleware(logRequests()).addHandler(router.call);

  final port = int.parse(Platform.environment['PORT'] ?? '8090');
  final server = await serve(handler, InternetAddress.anyIPv4, port);
  print('StockCalc backend listening on port ${server.port}');
}
