/// Real-time quotes from Yahoo Finance's public streaming endpoint
/// (`wss://streamer.finance.yahoo.com/?version=2`) - the same feed Yahoo's
/// own web pages use, and the one `yfinance`'s live streaming builds on. No
/// key or login. Unofficial: Yahoo can change it at any time, so everything
/// here degrades to "stream disconnected" (the scanner then shows Finviz's
/// delayed numbers) instead of failing.
///
/// Protocol (verified live 2026-11-12, US market open): send
/// `{"subscribe": [symbols]}` / `{"unsubscribe": [...]}`; receive JSON
/// `{"type":"pricing","message":"<base64 protobuf PricingData>"}` per trade.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum MarketSession { pre, regular, post, extended, unknown }

/// One decoded PricingData message (fields we use).
class PriceTick {
  final String symbol;
  final double price;
  final DateTime time;
  final double changePercent;
  final double change;
  final int dayVolume;
  final double dayHigh, dayLow;
  final int lastSize;
  final MarketSession session;
  final String exchange;

  const PriceTick({
    required this.symbol,
    required this.price,
    required this.time,
    this.changePercent = 0,
    this.change = 0,
    this.dayVolume = 0,
    this.dayHigh = 0,
    this.dayLow = 0,
    this.lastSize = 0,
    this.session = MarketSession.unknown,
    this.exchange = '',
  });

  /// Decodes the base64 `message` of a pricing frame. Field numbers follow
  /// Yahoo's PricingData proto (1 id, 2 price, 3 time ms (sint64), 5 exchange,
  /// 7 market hours, 8 change %, 9 day volume (sint64), 10/11 day high/low,
  /// 12 change, 22 last size (sint64)). Returns null for frames without a
  /// symbol/price.
  static PriceTick? decode(String base64Message) {
    final Map<int, Object> f;
    try {
      f = decodeProtobuf(base64Decode(base64Message));
    } on Object {
      return null;
    }
    final symbol = f[1];
    final price = f[2];
    if (symbol is! String || price is! double || symbol.isEmpty) return null;
    int zz(Object? v) => v is int ? (v >> 1) ^ -(v & 1) : 0;
    double dbl(Object? v) => v is double ? v : 0;
    final ms = zz(f[3]);
    return PriceTick(
      symbol: symbol,
      price: price,
      time: ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true) : DateTime.now().toUtc(),
      exchange: f[5] is String ? f[5] as String : '',
      session: switch (f[7]) {
        0 => MarketSession.pre,
        1 => MarketSession.regular,
        2 => MarketSession.post,
        3 => MarketSession.extended,
        _ => MarketSession.unknown,
      },
      changePercent: dbl(f[8]),
      dayVolume: zz(f[9]),
      dayHigh: dbl(f[10]),
      dayLow: dbl(f[11]),
      change: dbl(f[12]),
      lastSize: zz(f[22]),
    );
  }
}

/// Minimal protobuf wire-format reader: field number -> last value
/// (varint as int, fixed32 as float, fixed64 as double, bytes as UTF-8).
Map<int, Object> decodeProtobuf(Uint8List b) {
  final out = <int, Object>{};
  var i = 0;
  int varint() {
    var shift = 0, result = 0;
    while (true) {
      if (i >= b.length) throw const FormatException('truncated varint');
      final x = b[i++];
      result |= (x & 0x7f) << shift;
      if (x & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('varint too long');
    }
  }

  while (i < b.length) {
    final tag = varint();
    final field = tag >> 3;
    switch (tag & 7) {
      case 0:
        out[field] = varint();
      case 1:
        if (i + 8 > b.length) throw const FormatException('truncated fixed64');
        out[field] = ByteData.sublistView(b, i, i + 8).getFloat64(0, Endian.little);
        i += 8;
      case 2:
        final len = varint();
        if (i + len > b.length) throw const FormatException('truncated bytes');
        out[field] = utf8.decode(b.sublist(i, i + len), allowMalformed: true);
        i += len;
      case 5:
        if (i + 4 > b.length) throw const FormatException('truncated fixed32');
        out[field] = ByteData.sublistView(b, i, i + 4).getFloat32(0, Endian.little).toDouble();
        i += 4;
      default:
        throw FormatException('unsupported wire type ${tag & 7}');
    }
  }
  return out;
}

typedef SocketConnector = Future<WebSocket> Function(Uri url);

Future<WebSocket> _defaultConnect(Uri url) => WebSocket.connect(url.toString(), headers: {
      'Origin': 'https://finance.yahoo.com',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
    });

/// Keeps one WebSocket open, (re)subscribes the wanted symbols, reconnects
/// with backoff, and emits decoded [PriceTick]s.
class YahooStream {
  YahooStream({
    Uri? url,
    SocketConnector? connect,
    this.stallTimeout = const Duration(seconds: 90),
  })  : url = url ?? Uri.parse('wss://streamer.finance.yahoo.com/?version=2'),
        _connect = connect ?? _defaultConnect;

  final Uri url;
  final SocketConnector _connect;

  /// Reconnect when subscribed but nothing arrived for this long (silent
  /// dead connections happen; outside market hours some symbols are quiet,
  /// so this is generous).
  final Duration stallTimeout;

  final _ticks = StreamController<PriceTick>.broadcast();
  Stream<PriceTick> get ticks => _ticks.stream;

  final Set<String> _wanted = {};
  final Set<String> _subscribed = {};
  WebSocket? _ws;
  bool _running = false;
  int _attempt = 0;
  DateTime _lastMessage = DateTime.now();
  Timer? _watchdog;
  String? lastError;
  int messages = 0;

  bool get connected => _ws != null;

  void start() {
    if (_running) return;
    _running = true;
    _watchdog = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_ws != null && _wanted.isNotEmpty && DateTime.now().difference(_lastMessage) > stallTimeout) {
        lastError = 'stream stalled - reconnecting';
        _ws?.close();
      }
    });
    _loop();
  }

  Future<void> stop() async {
    _running = false;
    _watchdog?.cancel();
    await _ws?.close();
    _ws = null;
  }

  /// Desired symbol set; only the difference is sent to Yahoo.
  void setSymbols(Iterable<String> symbols) {
    _wanted
      ..clear()
      ..addAll(symbols.map((s) => s.toUpperCase()));
    _sync();
  }

  void _sync() {
    final ws = _ws;
    if (ws == null) return;
    final add = _wanted.difference(_subscribed).toList();
    final remove = _subscribed.difference(_wanted).toList();
    if (remove.isNotEmpty) ws.add(jsonEncode({'unsubscribe': remove}));
    if (add.isNotEmpty) ws.add(jsonEncode({'subscribe': add}));
    _subscribed
      ..removeAll(remove)
      ..addAll(add);
  }

  Future<void> _loop() async {
    while (_running) {
      try {
        final ws = await _connect(url).timeout(const Duration(seconds: 15));
        _ws = ws;
        _attempt = 0;
        lastError = null;
        _lastMessage = DateTime.now();
        _subscribed.clear();
        _sync();
        await for (final m in ws) {
          _lastMessage = DateTime.now();
          messages++;
          if (m is! String) continue;
          final Object? frame;
          try {
            frame = jsonDecode(m);
          } on FormatException {
            continue;
          }
          if (frame is Map && frame['type'] == 'pricing' && frame['message'] is String) {
            final t = PriceTick.decode(frame['message'] as String);
            if (t != null) _ticks.add(t);
          }
        }
        lastError ??= 'stream closed (${ws.closeCode ?? '-'})';
      } on Object catch (e) {
        lastError = 'stream error: $e';
      }
      _ws = null;
      _subscribed.clear();
      if (!_running) break;
      final waits = [1, 2, 5, 10, 20, 30];
      await Future<void>.delayed(Duration(seconds: waits[_attempt.clamp(0, waits.length - 1)]));
      _attempt++;
    }
  }
}
