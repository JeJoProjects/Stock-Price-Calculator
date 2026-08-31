/// Runs ScreenerService's polling loop on its own Dart isolate, so the
/// (fairly slow — one HTTP request every ~1.1s across the whole ticker
/// universe) screener poll never competes with the HTTP server's request
/// handling. Results stream back over a SendPort as plain JSON-safe maps.
library;

import 'dart:async';
import 'dart:isolate';
import 'finnhub_client.dart';
import 'screener_criteria.dart';
import 'screener_service.dart';
import 'ticker_universe.dart';

void _isolateMain(Map<String, dynamic> init) {
  final sendPort = init['sendPort'] as SendPort;
  final client = FinnhubClient(apiKey: init['apiKey'] as String);
  final criteria = ScreenerCriteria(
    maxMarketCap: init['maxMarketCap'] as double,
    minChangePercent: init['minChangePercent'] as double,
  );
  final overrideList = init['tickerUniverse'] as List?;
  final service = ScreenerService(
    client: client,
    criteria: criteria,
    pollInterval: Duration(seconds: init['pollIntervalSeconds'] as int),
    requestSpacing: Duration(milliseconds: init['requestSpacingMs'] as int),
    tickerUniverseOverride: overrideList == null
        ? null
        : [
            for (final t in overrideList)
              TickerInfo(
                symbol: (t as Map)['symbol'] as String,
                name: t['name'] as String,
                exchange: t['exchange'] as String,
              ),
          ],
    onUpdate: (rows, updatedAt, error) {
      sendPort.send({
        'rows': rows.map((r) => r.toJson()).toList(),
        'lastUpdated': updatedAt.toIso8601String(),
        'error': error,
      });
    },
  );
  service.start();
}

/// Main-isolate handle: spawns the worker isolate and keeps the latest
/// result available synchronously for the HTTP handler to read.
class ScreenerIsolateRunner {
  List<ScreenerRow> latest = [];
  DateTime? lastUpdated;
  String? lastError;

  Isolate? _isolate;
  ReceivePort? _receivePort;

  Future<void> start({
    required String apiKey,
    ScreenerCriteria criteria = const ScreenerCriteria(),
    Duration pollInterval = const Duration(minutes: 5),
    Duration requestSpacing = const Duration(milliseconds: 1100),
    List<TickerInfo>? tickerUniverseOverride,
  }) async {
    final receivePort = ReceivePort();
    _receivePort = receivePort;

    receivePort.listen((message) {
      final map = message as Map<String, dynamic>;
      latest = (map['rows'] as List)
          .map((r) => ScreenerRow.fromJson(r as Map<String, dynamic>))
          .toList();
      lastUpdated = DateTime.tryParse(map['lastUpdated'] as String);
      lastError = map['error'] as String?;
    });

    _isolate = await Isolate.spawn(_isolateMain, {
      'sendPort': receivePort.sendPort,
      'apiKey': apiKey,
      'maxMarketCap': criteria.maxMarketCap,
      'minChangePercent': criteria.minChangePercent,
      'pollIntervalSeconds': pollInterval.inSeconds,
      'requestSpacingMs': requestSpacing.inMilliseconds,
      'tickerUniverse': tickerUniverseOverride
          ?.map((t) => {'symbol': t.symbol, 'name': t.name, 'exchange': t.exchange})
          .toList(),
    });
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
  }
}
