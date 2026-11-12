/// Client-side mirror of the backend's live scanner rows
/// (backend/lib/live_scanner.dart `rows()` / `snapshot()`), plus the views
/// (presets), filters and alert detection the Scanner tab applies to them.
/// Pure Dart, no Flutter - unit-tested in test/scanner_models_test.dart.
library;

double _d(Object? v) => v is num ? v.toDouble() : 0;

class ScannerRow {
  final String symbol;
  final String name;
  final String sector;
  final String industry;
  final String country;
  final double price;
  final double prevClose;
  final double changePercent;
  final double gapPercent;
  final double volume;
  final double avgVolume;
  final double relVolume;
  final double floatShares;
  final double shortFloat;
  final double marketCap;
  final double change1m;
  final double change5m;
  final double high;
  final int momentum;
  final Set<String> flags;

  /// True once a real-time trade arrived; false = Finviz's delayed numbers.
  final bool live;
  final String session;
  final DateTime? lastTrade;

  /// Increments per trade - lets the UI flash a cell exactly once per tick.
  final int seq;

  /// Direction of the last trade: 1 up, -1 down, 0 none yet.
  final int dir;

  const ScannerRow({
    required this.symbol,
    this.name = '',
    this.sector = '',
    this.industry = '',
    this.country = '',
    required this.price,
    this.prevClose = 0,
    required this.changePercent,
    this.gapPercent = 0,
    this.volume = 0,
    this.avgVolume = 0,
    this.relVolume = 0,
    this.floatShares = 0,
    this.shortFloat = 0,
    this.marketCap = 0,
    this.change1m = 0,
    this.change5m = 0,
    this.high = 0,
    this.momentum = 0,
    this.flags = const {},
    this.live = false,
    this.session = 'unknown',
    this.lastTrade,
    this.seq = 0,
    this.dir = 0,
  });

  factory ScannerRow.fromJson(Map<String, dynamic> j) => ScannerRow(
        symbol: j['symbol'] as String? ?? '',
        name: j['name'] as String? ?? '',
        sector: j['sector'] as String? ?? '',
        industry: j['industry'] as String? ?? '',
        country: j['country'] as String? ?? '',
        price: _d(j['price']),
        prevClose: _d(j['prevClose']),
        changePercent: _d(j['changePercent']),
        gapPercent: _d(j['gapPercent']),
        volume: _d(j['volume']),
        avgVolume: _d(j['avgVolume']),
        relVolume: _d(j['relVolume']),
        floatShares: _d(j['floatShares']),
        shortFloat: _d(j['shortFloat']),
        marketCap: _d(j['marketCap']),
        change1m: _d(j['change1m']),
        change5m: _d(j['change5m']),
        high: _d(j['high']),
        momentum: (j['momentum'] as num?)?.toInt() ?? 0,
        flags: {...((j['flags'] as List?) ?? const []).whereType<String>()},
        live: j['live'] as bool? ?? false,
        session: j['session'] as String? ?? 'unknown',
        lastTrade: j['lastTrade'] is num
            ? DateTime.fromMillisecondsSinceEpoch((j['lastTrade'] as num).toInt(), isUtc: true)
            : null,
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        dir: (j['dir'] as num?)?.toInt() ?? 0,
      );

  bool get lowFloat => flags.contains('lowFloat');
  bool get relVolSpike => flags.contains('relVolSpike');
  bool get newHigh => flags.contains('newHigh');
  bool get highShort => flags.contains('highShort');
}

class ScannerSnapshot {
  final List<ScannerRow> rows;
  final DateTime? asOf;
  final DateTime? universeUpdated;
  final String? universeError;
  final bool streamConnected;
  final String? streamError;
  final int streamMessages;
  final String session;

  const ScannerSnapshot({
    this.rows = const [],
    this.asOf,
    this.universeUpdated,
    this.universeError,
    this.streamConnected = false,
    this.streamError,
    this.streamMessages = 0,
    this.session = 'unknown',
  });

  factory ScannerSnapshot.fromJson(Map<String, dynamic> j) {
    final stream = (j['stream'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ScannerSnapshot(
      rows: [
        for (final r in (j['rows'] as List? ?? const []).whereType<Map>()) ScannerRow.fromJson(r.cast<String, dynamic>()),
      ],
      asOf: DateTime.tryParse(j['asOf'] as String? ?? ''),
      universeUpdated: DateTime.tryParse(j['universeUpdated'] as String? ?? ''),
      universeError: j['universeError'] as String?,
      streamConnected: stream['connected'] as bool? ?? false,
      streamError: stream['error'] as String?,
      streamMessages: (stream['messages'] as num?)?.toInt() ?? 0,
      session: j['session'] as String? ?? 'unknown',
    );
  }
}

/// The scanner's preset views (the "Top Gainers" dropdown / tabs).
enum ScannerView {
  momentum('Momentum', 'Fastest movers right now: 5-min and 1-min change, relative volume'),
  topGainers('Top Gainers', 'Biggest % gain vs. previous close'),
  topGappers('Top Gappers', 'Biggest opening gap'),
  relVolume('Rel Volume', 'Most unusual volume vs. a normal day'),
  lowFloat('Low Float', 'Under 10M shares float, gainers first'),
  newHighs('New Highs', 'Trading at the high of the day and rising'),
  topLosers('Top Losers', 'Biggest % loss vs. previous close');

  const ScannerView(this.label, this.description);
  final String label;
  final String description;
}

/// User filters (the "Filter" button). Zero/null = no limit.
class ScannerFilter {
  final double minPrice;
  final double maxPrice;
  final double minRelVolume;
  final double maxFloatMillions;
  final double minVolume;
  final bool liveOnly;

  const ScannerFilter({
    this.minPrice = 0,
    this.maxPrice = 0,
    this.minRelVolume = 0,
    this.maxFloatMillions = 0,
    this.minVolume = 0,
    this.liveOnly = false,
  });

  bool get isActive =>
      minPrice > 0 || maxPrice > 0 || minRelVolume > 0 || maxFloatMillions > 0 || minVolume > 0 || liveOnly;

  bool accepts(ScannerRow r) =>
      (minPrice <= 0 || r.price >= minPrice) &&
      (maxPrice <= 0 || r.price <= maxPrice) &&
      (minRelVolume <= 0 || r.relVolume >= minRelVolume) &&
      (maxFloatMillions <= 0 || (r.floatShares > 0 && r.floatShares <= maxFloatMillions * 1e6)) &&
      (minVolume <= 0 || r.volume >= minVolume) &&
      (!liveOnly || r.live);

  ScannerFilter copyWith({
    double? minPrice,
    double? maxPrice,
    double? minRelVolume,
    double? maxFloatMillions,
    double? minVolume,
    bool? liveOnly,
  }) =>
      ScannerFilter(
        minPrice: minPrice ?? this.minPrice,
        maxPrice: maxPrice ?? this.maxPrice,
        minRelVolume: minRelVolume ?? this.minRelVolume,
        maxFloatMillions: maxFloatMillions ?? this.maxFloatMillions,
        minVolume: minVolume ?? this.minVolume,
        liveOnly: liveOnly ?? this.liveOnly,
      );
}

/// Rows for one view: filtered, then ordered by the view's key. A text
/// [query] narrows by symbol or company name.
List<ScannerRow> applyView(List<ScannerRow> rows, ScannerView view, ScannerFilter filter, {String query = ''}) {
  final q = query.trim().toUpperCase();
  bool matches(ScannerRow r) =>
      filter.accepts(r) && (q.isEmpty || r.symbol.contains(q) || r.name.toUpperCase().contains(q));
  final out = rows.where(matches).where((r) => switch (view) {
        ScannerView.topGainers => r.changePercent > 0,
        ScannerView.topLosers => r.changePercent < 0,
        ScannerView.topGappers => r.gapPercent > 0,
        ScannerView.lowFloat => r.lowFloat && r.changePercent > 0,
        ScannerView.newHighs => r.newHigh,
        ScannerView.momentum || ScannerView.relVolume => true,
      }).toList();
  int byDesc(double a, double b) => b.compareTo(a);
  out.sort((a, b) => switch (view) {
        ScannerView.momentum => b.momentum != a.momentum ? b.momentum - a.momentum : byDesc(a.change5m, b.change5m),
        ScannerView.topGainers || ScannerView.lowFloat || ScannerView.newHighs => byDesc(a.changePercent, b.changePercent),
        ScannerView.topGappers => byDesc(a.gapPercent, b.gapPercent),
        ScannerView.relVolume => byDesc(a.relVolume, b.relVolume),
        ScannerView.topLosers => a.changePercent.compareTo(b.changePercent),
      });
  return out;
}

/// One alert: a stock that just started a move worth looking at.
class ScannerAlert {
  final String symbol;
  final String reason;
  final double price;
  final double changePercent;
  final DateTime time;
  const ScannerAlert(this.symbol, this.reason, this.price, this.changePercent, this.time);
}

/// Detects alert-worthy changes between snapshots: a stock newly hitting a
/// high of day with momentum, a relative-volume spike appearing, or a jump
/// into the top [topN] gainers. Each symbol+reason fires at most once per
/// [cooldown], so a stock grinding up doesn't spam.
class AlertTracker {
  AlertTracker({this.topN = 10, this.minMomentum = 50, this.cooldown = const Duration(minutes: 5)});

  final int topN;
  final int minMomentum;
  final Duration cooldown;
  final Map<String, DateTime> _lastFired = {};
  Map<String, ScannerRow>? _previous;
  Set<String> _previousTop = {};

  List<ScannerAlert> update(List<ScannerRow> rows, DateTime now) {
    final gainers = [...rows.where((r) => r.changePercent > 0)]
      ..sort((a, b) => b.changePercent.compareTo(a.changePercent));
    final top = gainers.take(topN).map((r) => r.symbol).toSet();
    final prev = _previous;
    _previous = {for (final r in rows) r.symbol: r};
    final prevTop = _previousTop;
    _previousTop = top;
    if (prev == null) return const []; // first snapshot is the baseline

    final out = <ScannerAlert>[];
    void fire(ScannerRow r, String reason) {
      final key = '${r.symbol}|$reason';
      final last = _lastFired[key];
      if (last != null && now.difference(last) < cooldown) return;
      _lastFired[key] = now;
      out.add(ScannerAlert(r.symbol, reason, r.price, r.changePercent, now));
    }

    for (final r in rows) {
      if (!r.live) continue;
      final p = prev[r.symbol];
      if (r.newHigh && r.momentum >= minMomentum && !(p?.newHigh ?? false)) fire(r, 'New high, momentum ${r.momentum}');
      if (r.relVolSpike && p != null && !p.relVolSpike) fire(r, 'Volume spike ${r.relVolume.toStringAsFixed(1)}x');
      if (top.contains(r.symbol) && !prevTop.contains(r.symbol) && prevTop.isNotEmpty) fire(r, 'Entered top $topN gainers');
    }
    return out;
  }
}
