import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/scanner/scanner_client.dart';
import 'package:stockcalc/scanner/scanner_models.dart';

ScannerRow _r(
  String s, {
  double chg = 0,
  double gap = 0,
  double price = 5,
  double relVol = 1,
  double float = 0,
  int momo = 0,
  double c5 = 0,
  Set<String> flags = const {},
  bool live = true,
}) =>
    ScannerRow(
      symbol: s,
      name: '$s Holdings',
      price: price,
      changePercent: chg,
      gapPercent: gap,
      relVolume: relVol,
      floatShares: float,
      momentum: momo,
      change5m: c5,
      flags: flags,
      live: live,
    );

void main() {
  test('parses a backend snapshot', () {
    final snap = ScannerSnapshot.fromJson({
      'type': 'snapshot',
      'asOf': '2026-11-12T20:00:00.000Z',
      'universeUpdated': '2026-11-12T19:59:30.000Z',
      'universeError': null,
      'stream': {'connected': true, 'error': null, 'messages': 42},
      'session': 'regular',
      'rows': [
        {
          'symbol': 'ABCD',
          'name': 'Abcd Inc',
          'price': 3.25,
          'changePercent': 41.3,
          'gapPercent': 12,
          'volume': 1.5e7,
          'relVolume': 9.5,
          'floatShares': 4.2e6,
          'momentum': 81,
          'flags': ['lowFloat', 'newHigh', 'unusualVolume'],
          'live': true,
          'lastTrade': 1794513600000,
          'seq': 7,
          'dir': 1,
        },
      ],
    });
    expect(snap.streamConnected, isTrue);
    expect(snap.streamMessages, 42);
    expect(snap.session, 'regular');
    final r = snap.rows.single;
    expect(r.symbol, 'ABCD');
    expect(r.gapPercent, 12.0);
    expect(r.lowFloat && r.newHigh, isTrue);
    expect(r.relVolSpike, isFalse);
    expect(r.lastTrade!.isUtc, isTrue);
    expect(r.seq, 7);
  });

  test('views filter and order rows', () {
    final rows = [
      _r('UP', chg: 20, gap: 5, relVol: 3, momo: 40),
      _r('BIG', chg: 60, gap: 30, relVol: 12, momo: 20, float: 3e6, flags: {'lowFloat'}),
      _r('DOWN', chg: -15, relVol: 30, momo: 0),
      _r('HOT', chg: 8, momo: 90, c5: 4, flags: {'newHigh'}),
    ];
    List<String> syms(ScannerView v, [ScannerFilter f = const ScannerFilter()]) =>
        applyView(rows, v, f).map((r) => r.symbol).toList();
    expect(syms(ScannerView.topGainers), ['BIG', 'UP', 'HOT']);
    expect(syms(ScannerView.topLosers), ['DOWN']);
    expect(syms(ScannerView.topGappers), ['BIG', 'UP']);
    expect(syms(ScannerView.relVolume), ['DOWN', 'BIG', 'UP', 'HOT']);
    expect(syms(ScannerView.momentum).first, 'HOT');
    expect(syms(ScannerView.lowFloat), ['BIG']);
    expect(syms(ScannerView.newHighs), ['HOT']);
    expect(applyView(rows, ScannerView.topGainers, const ScannerFilter(), query: 'hold').length, 3);
    expect(applyView(rows, ScannerView.topGainers, const ScannerFilter(), query: 'bi').single.symbol, 'BIG');
  });

  test('filter limits', () {
    const f = ScannerFilter(minPrice: 1, maxPrice: 10, minRelVolume: 2, maxFloatMillions: 20, liveOnly: true);
    expect(f.isActive, isTrue);
    expect(f.accepts(_r('OK', price: 5, relVol: 3, float: 10e6)), isTrue);
    expect(f.accepts(_r('PRICEY', price: 50, relVol: 3, float: 10e6)), isFalse);
    expect(f.accepts(_r('QUIET', price: 5, relVol: 1, float: 10e6)), isFalse);
    expect(f.accepts(_r('UNKNOWNFLOAT', price: 5, relVol: 3)), isFalse);
    expect(f.accepts(_r('STALE', price: 5, relVol: 3, float: 10e6, live: false)), isFalse);
    expect(const ScannerFilter().isActive, isFalse);
  });

  test('alerts fire on new events only, once per cooldown', () {
    final tracker = AlertTracker(topN: 2);
    final t0 = DateTime(2026, 11, 12, 15);
    expect(tracker.update([_r('A', chg: 10), _r('B', chg: 5), _r('C', chg: 1)], t0), isEmpty); // baseline

    var alerts = tracker.update([
      _r('A', chg: 10),
      _r('B', chg: 5),
      _r('C', chg: 20, momo: 80, flags: {'newHigh', 'relVolSpike'}),
    ], t0.add(const Duration(seconds: 1)));
    expect(alerts.map((a) => a.symbol).toSet(), {'C'});
    expect(alerts.map((a) => a.reason).join('|'), allOf(contains('New high'), contains('Volume spike'), contains('top 2')));

    // Flags drop and come back within the cooldown: no repeat.
    tracker.update([_r('A', chg: 10), _r('C', chg: 20)], t0.add(const Duration(seconds: 2)));
    alerts = tracker.update([
      _r('A', chg: 10),
      _r('C', chg: 20, momo: 80, flags: {'newHigh'}),
    ], t0.add(const Duration(seconds: 3)));
    expect(alerts, isEmpty);
  });

  test('client streams snapshots from the live socket and reconnects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var connections = 0;
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      connections++;
      ws.add(jsonEncode({
        'type': 'snapshot',
        'rows': [
          {'symbol': 'C$connections', 'price': 1, 'changePercent': 2},
        ],
      }));
      if (connections == 1) await ws.close(); // force one reconnect
    });
    final client = ScannerClient(url: Uri.parse('ws://127.0.0.1:${server.port}/live'));
    final got = <String>[];
    final done = Completer<void>();
    client.snapshots.listen((s) {
      got.add(s.rows.single.symbol);
      if (got.length == 2 && !done.isCompleted) done.complete();
    });
    client.start();
    await done.future.timeout(const Duration(seconds: 10));
    expect(got, ['C1', 'C2']);
    expect(client.link, ScannerLink.connected);
    await client.dispose();
    await server.close(force: true);
  });
}
