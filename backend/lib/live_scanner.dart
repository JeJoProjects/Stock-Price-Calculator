/// The live momentum scanner: Finviz decides WHICH stocks are on the screen
/// (unusual volume + top gainers, refreshed about once a minute, delayed
/// data but rich fundamentals: float, gap, average/relative volume), Yahoo's
/// stream supplies real-time price/volume per trade. The merge adds derived
/// live numbers: change vs previous close, live relative volume, 1/5-minute
/// change, high of day, and a momentum score.
library;

import 'dart:async';
import 'dart:math' as math;
import 'finviz_client.dart';
import 'yahoo_stream.dart';

/// A Finviz screen that feeds the universe: signal + page cap + label.
class UniverseSource {
  final String signal;
  final int maxPages;
  final String tag;
  const UniverseSource(this.signal, this.maxPages, this.tag);
}

const defaultUniverse = [
  UniverseSource('ta_unusualvolume', 10, 'unusualVolume'),
  UniverseSource('ta_topgainers', 8, 'topGainer'),
];

class _History {
  final List<(int, double)> points = [];

  void add(int ms, double price) {
    if (points.isNotEmpty && ms - points.last.$1 < 1000) {
      points[points.length - 1] = (points.last.$1, price); // 1 sample/second
    } else {
      points.add((ms, price));
    }
    final cutoff = ms - const Duration(minutes: 6).inMilliseconds;
    while (points.length > 2 && points.first.$1 < cutoff) {
      points.removeAt(0);
    }
  }

  /// Percent change from the price [window] ago (oldest sample inside the
  /// window if the history is shorter) to [price]. 0 if unknown.
  double changeOver(Duration window, double price, int nowMs) {
    if (points.isEmpty || price <= 0) return 0;
    final from = nowMs - window.inMilliseconds;
    (int, double)? base;
    for (final p in points) {
      if (p.$1 >= from) {
        base = p;
        break;
      }
    }
    base ??= points.last;
    if (base.$2 <= 0) return 0;
    return (price - base.$2) / base.$2 * 100;
  }
}

class _State {
  _State(this.finviz, this.tags);
  FinvizRow finviz;
  Set<String> tags;
  PriceTick? tick;
  final history = _History();
  double highSeen = 0;
  int seq = 0;
  int lastDirection = 0;
}

/// Momentum score 0..100 for upward movers (documented heuristic):
/// 40% 5-minute change (5% = full), 25% 1-minute change (2% = full),
/// 20% relative volume (10x = full), 15% day change (30% = full).
/// Downward movement contributes nothing.
int momentumScore({required double change5m, required double change1m, required double relVolume, required double changePercent}) {
  double c(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0);
  final s = 40 * c(change5m / 5) + 25 * c(change1m / 2) + 20 * c((relVolume - 1) / 9) + 15 * c(changePercent / 30);
  return s.round();
}

class LiveScanner {
  LiveScanner({
    required this.finviz,
    required this.stream,
    this.universe = defaultUniverse,
    this.refreshInterval = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final FinvizClient finviz;
  final YahooStream stream;
  final List<UniverseSource> universe;
  final Duration refreshInterval;
  final DateTime Function() _now;

  final Map<String, _State> _states = {};
  final _changes = StreamController<void>.broadcast();
  StreamSubscription<PriceTick>? _sub;
  Timer? _timer;
  bool _refreshing = false;
  Duration _backoff = Duration.zero;

  DateTime? universeUpdated;
  String? universeError;
  MarketSession lastSession = MarketSession.unknown;
  int version = 0;

  /// Fires (coalesce downstream) whenever any row changed.
  Stream<void> get changes => _changes.stream;

  void start() {
    _sub = stream.ticks.listen(applyTick);
    stream.start();
    refreshUniverse();
    _timer = Timer.periodic(refreshInterval, (_) => refreshUniverse());
  }

  Future<void> stop() async {
    _timer?.cancel();
    await _sub?.cancel();
    await stream.stop();
  }

  /// Re-reads the Finviz screens and updates the stream subscription.
  Future<void> refreshUniverse() async {
    if (_refreshing) return;
    if (_backoff > Duration.zero && universeUpdated != null &&
        _now().difference(universeUpdated!) < _backoff) {
      return;
    }
    _refreshing = true;
    try {
      final next = <String, (FinvizRow, Set<String>)>{};
      for (final src in universe) {
        final rows = await finviz.fetchAll(signal: src.signal, maxPages: src.maxPages);
        for (final r in rows) {
          final e = next[r.symbol];
          next[r.symbol] = e == null ? (r, {src.tag}) : (e.$1, {...e.$2, src.tag});
        }
      }
      setUniverse(next);
      universeError = null;
      _backoff = Duration.zero;
    } on FinvizRateLimited catch (e) {
      universeError = '$e';
      _backoff = _backoff == Duration.zero ? const Duration(minutes: 2) : _backoff * 2;
      if (_backoff > const Duration(minutes: 15)) _backoff = const Duration(minutes: 15);
    } on Object catch (e) {
      universeError = 'Finviz refresh failed: $e';
    } finally {
      _refreshing = false;
      _bump();
    }
  }

  /// Replaces the universe (keeps live state of symbols that stay).
  void setUniverse(Map<String, (FinvizRow, Set<String>)> rows) {
    _states.removeWhere((s, _) => !rows.containsKey(s));
    for (final e in rows.entries) {
      final st = _states[e.key];
      if (st == null) {
        _states[e.key] = _State(e.value.$1, e.value.$2);
      } else {
        st
          ..finviz = e.value.$1
          ..tags = e.value.$2;
      }
    }
    universeUpdated = _now();
    stream.setSymbols(_states.keys);
  }

  void applyTick(PriceTick t) {
    final st = _states[t.symbol];
    if (st == null || t.price <= 0) return;
    final prev = st.tick?.price ?? st.finviz.price;
    st.lastDirection = t.price > prev ? 1 : (t.price < prev ? -1 : st.lastDirection);
    st.tick = t;
    st.seq++;
    st.history.add(t.time.millisecondsSinceEpoch, t.price);
    st.highSeen = math.max(st.highSeen, math.max(t.price, t.dayHigh));
    if (t.session != MarketSession.unknown) lastSession = t.session;
    _bump();
  }

  void _bump() {
    version++;
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Current rows, ready for JSON. Sorted by change % descending.
  List<Map<String, Object?>> rows() {
    final nowMs = _now().millisecondsSinceEpoch;
    final out = <Map<String, Object?>>[];
    for (final e in _states.entries) {
      final st = e.value;
      final f = st.finviz;
      final t = st.tick;
      final price = t?.price ?? f.price;
      final prevClose = f.prevClose > 0 ? f.prevClose : (t != null && t.change != 0 ? t.price - t.change : 0.0);
      final changePct = prevClose > 0 ? (price - prevClose) / prevClose * 100 : (t?.changePercent ?? f.changePercent);
      final volume = math.max(t?.dayVolume.toDouble() ?? 0, f.volume);
      final relVol = f.volume > 0 && f.relativeVolume > 0
          ? f.relativeVolume * (volume / f.volume)
          : (f.averageVolume > 0 ? volume / f.averageVolume : 0.0);
      final c1 = st.history.changeOver(const Duration(minutes: 1), price, nowMs);
      final c5 = st.history.changeOver(const Duration(minutes: 5), price, nowMs);
      final high = math.max(st.highSeen, price);
      final flags = <String>[
        if (f.floatShares > 0 && f.floatShares < 10e6) 'lowFloat',
        if (relVol >= 5) 'relVolSpike',
        if (t != null && price >= high && c1 > 0) 'newHigh',
        if (f.shortFloatPercent >= 20) 'highShort',
        ...st.tags,
      ];
      out.add({
        'symbol': e.key,
        'name': f.company,
        'sector': f.sector,
        'industry': f.industry,
        'country': f.country,
        'price': _r(price, 4),
        'prevClose': _r(prevClose, 4),
        'changePercent': _r(changePct, 2),
        'gapPercent': _r(f.gapPercent, 2),
        'volume': volume,
        'avgVolume': f.averageVolume.roundToDouble(),
        'relVolume': _r(relVol, 2),
        'floatShares': f.floatShares,
        'shortFloat': _r(f.shortFloatPercent, 1),
        'marketCap': f.marketCap,
        'change1m': _r(c1, 2),
        'change5m': _r(c5, 2),
        'high': _r(high, 4),
        'momentum': momentumScore(change5m: c5, change1m: c1, relVolume: relVol, changePercent: changePct),
        'flags': flags,
        'live': t != null,
        'session': t?.session.name ?? 'unknown',
        'lastTrade': t?.time.millisecondsSinceEpoch,
        'seq': st.seq,
        'dir': st.lastDirection,
      });
    }
    out.sort((a, b) => (b['changePercent'] as double).compareTo(a['changePercent'] as double));
    return out;
  }

  Map<String, Object?> snapshot() => {
        'type': 'snapshot',
        'version': version,
        'asOf': _now().toUtc().toIso8601String(),
        'universeUpdated': universeUpdated?.toUtc().toIso8601String(),
        'universeError': universeError,
        'stream': {'connected': stream.connected, 'error': stream.lastError, 'messages': stream.messages},
        'session': lastSession.name,
        'rows': rows(),
      };

  static double _r(double v, int digits) {
    if (v.isNaN || v.isInfinite) return 0;
    final p = math.pow(10, digits);
    return (v * p).round() / p;
  }
}
