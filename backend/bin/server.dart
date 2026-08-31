import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:backend/finnhub_client.dart';
import 'package:backend/market_types.dart';
import 'package:backend/screener_criteria.dart';
import 'package:backend/screener_isolate.dart';
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
  final screener = ScreenerIsolateRunner();
  if (client.hasApiKey) {
    await screener.start(
      apiKey: apiKey,
      criteria: const ScreenerCriteria(maxMarketCap: 500e6, minChangePercent: 10.0),
    );
  }

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
