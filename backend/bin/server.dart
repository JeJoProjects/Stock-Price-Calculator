import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:backend/finnhub_client.dart';
import 'package:backend/finviz_client.dart';
import 'package:backend/finviz_screener_service.dart';
import 'package:backend/market_types.dart';
import 'package:backend/symbol_search.dart';

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

  // Micro-Cap Movers is fed straight from Finviz's free screener page
  // (finviz_client.dart) - no account or key needed, unlike Finnhub above.
  final finvizClient = FinvizClient();
  // How often the backend re-fetches Finviz's screener page - the app's
  // Settings > Display "Movers Refresh" control only governs how often the
  // app re-fetches this already-computed, cached result, not how often the
  // backend talks to Finviz.
  final pollSeconds = int.tryParse(Platform.environment['SCREENER_POLL_SECONDS'] ?? '') ?? 30;
  final screener = FinvizScreenerService(
    client: finvizClient,
    pollInterval: Duration(seconds: pollSeconds),
  );
  screener.start();

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
    ..get('/screener/top', (Request req) {
      return _json({
        'rows': screener.latest.map((r) => r.toJson()).toList(),
        'lastUpdated': screener.lastUpdated?.toIso8601String(),
        'error': screener.lastError,
      });
    });

  final handler = Pipeline().addMiddleware(logRequests()).addHandler(router.call);

  final port = int.parse(Platform.environment['PORT'] ?? '8090');
  final server = await serve(handler, InternetAddress.anyIPv4, port);
  print('StockCalc backend listening on port ${server.port}');
}
