import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/formatting.dart';
import '../scanner/scanner_client.dart';
import '../scanner/scanner_models.dart';
import '../theme/app_theme.dart';

/// The live momentum scanner tab: the backend pushes snapshots over a local
/// WebSocket several times a second (Finviz picks the stocks about once a
/// minute, Yahoo's stream prices them per trade), so there's no refresh
/// button - cells flash as trades arrive. Views are presets ("Top Gainers",
/// "Momentum", ...), the Filter narrows by price/float/volume, and Alerts
/// (optionally with a sound) call out stocks that just started moving.
class ScannerPanel extends StatefulWidget {
  final ScannerClient client;

  /// Opens a stock in the Calculator tab (purchase panel + chart).
  final void Function(ScannerRow row) onOpen;

  const ScannerPanel({super.key, required this.client, required this.onOpen});

  @override
  State<ScannerPanel> createState() => _ScannerPanelState();
}

enum _Col { rank, symbol, price, change, gap, volume, relVol, float, c1, c5, momo, sector }

class _ScannerPanelState extends State<ScannerPanel> {
  ScannerSnapshot _snap = const ScannerSnapshot();
  ScannerLink _link = ScannerLink.connecting;
  ScannerView _view = ScannerView.topGainers;
  ScannerFilter _filter = const ScannerFilter();
  String _query = '';
  _Col? _sortCol;
  bool _sortAsc = false;
  String? _selected;
  bool _sound = false;
  bool _showAlerts = true;
  int _unseenAlerts = 0;

  final _alerts = <ScannerAlert>[];
  final _tracker = AlertTracker();
  final _seq = <String, int>{};
  final _flashAt = <String, DateTime>{};
  final _flashDir = <String, int>{};
  final List<StreamSubscription<Object>> _subs = [];
  Timer? _clock;

  static const _flashTime = Duration(milliseconds: 700);
  static const _rowHeight = 30.0;

  @override
  void initState() {
    super.initState();
    _subs.add(widget.client.snapshots.listen(_onSnapshot));
    _subs.add(widget.client.links.listen((l) {
      if (mounted) setState(() => _link = l);
    }));
    if (widget.client.latest != null) _snap = widget.client.latest!;
    _link = widget.client.link;
    widget.client.start();
    // Keeps the "updated Xs ago" labels honest between pushes.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _clock?.cancel();
    super.dispose();
  }

  void _onSnapshot(ScannerSnapshot s) {
    if (!mounted) return;
    final now = DateTime.now();
    for (final r in s.rows) {
      final before = _seq[r.symbol];
      if (before != null && r.seq != before) {
        _flashAt[r.symbol] = now;
        _flashDir[r.symbol] = r.dir;
      }
      _seq[r.symbol] = r.seq;
    }
    final fresh = _tracker.update(s.rows, now);
    if (fresh.isNotEmpty) {
      _alerts.insertAll(0, fresh);
      if (_alerts.length > 200) _alerts.removeRange(200, _alerts.length);
      if (!_showAlerts) _unseenAlerts += fresh.length;
      if (_sound) SystemSound.play(SystemSoundType.alert);
    }
    setState(() => _snap = s);
  }

  List<ScannerRow> get _rows {
    final rows = applyView(_snap.rows, _view, _filter, query: _query);
    final col = _sortCol;
    if (col == null) return rows;
    double key(ScannerRow r) => switch (col) {
          _Col.price => r.price,
          _Col.change => r.changePercent,
          _Col.gap => r.gapPercent,
          _Col.volume => r.volume,
          _Col.relVol => r.relVolume,
          _Col.float => r.floatShares > 0 ? r.floatShares : double.infinity,
          _Col.c1 => r.change1m,
          _Col.c5 => r.change5m,
          _Col.momo => r.momentum.toDouble(),
          _ => 0,
        };
    if (col == _Col.symbol || col == _Col.sector) {
      rows.sort((a, b) {
        final c = col == _Col.symbol ? a.symbol.compareTo(b.symbol) : a.sector.compareTo(b.sector);
        return _sortAsc ? c : -c;
      });
    } else {
      rows.sort((a, b) => _sortAsc ? key(a).compareTo(key(b)) : key(b).compareTo(key(a)));
    }
    return rows;
  }

  ScannerRow? get _selectedRow {
    for (final r in _snap.rows) {
      if (r.symbol == _selected) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Container(
      color: AppColors.bgPrimary,
      child: Column(
        children: [
          _toolbar(),
          _statusStrip(rows.length),
          if (_snap.universeError != null) _banner(_snap.universeError!),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _table(rows)),
                if (_showAlerts) _alertsPane(),
              ],
            ),
          ),
          if (_selectedRow != null) _details(_selectedRow!),
        ],
      ),
    );
  }

  // ---- toolbar -----------------------------------------------------------

  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final v in ScannerView.values) _viewChip(v),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            height: 30,
            child: TextField(
              style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Find symbol…',
                hintStyle: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                prefixIcon: Icon(Icons.search, size: 16, color: AppColors.textMuted),
                prefixIconConstraints: BoxConstraints(minWidth: 30),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(width: 6),
          _toolButton(
            icon: Icons.filter_list,
            label: _filter.isActive ? 'Filter •' : 'Filter',
            active: _filter.isActive,
            tooltip: 'Price, float, volume and relative-volume limits',
            onTap: _openFilter,
          ),
          _toolButton(
            icon: _sound ? Icons.volume_up : Icons.volume_off,
            label: 'Sound',
            active: _sound,
            tooltip: 'Beep when an alert fires',
            onTap: () => setState(() => _sound = !_sound),
          ),
          _toolButton(
            icon: Icons.notifications_active_outlined,
            label: _unseenAlerts > 0 ? 'Alerts ($_unseenAlerts)' : 'Alerts',
            active: _showAlerts,
            tooltip: 'New highs with momentum, volume spikes, new top-10 gainers',
            onTap: () => setState(() {
              _showAlerts = !_showAlerts;
              if (_showAlerts) _unseenAlerts = 0;
            }),
          ),
        ],
      ),
    );
  }

  Widget _viewChip(ScannerView v) {
    final selected = v == _view;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: v.description,
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          borderRadius: BorderRadius.circular(kInputRadius),
          onTap: () => setState(() {
            _view = v;
            _sortCol = null; // a preset defines its own order
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? AppColors.accentBlue : AppColors.bgInput,
              borderRadius: BorderRadius.circular(kInputRadius),
            ),
            child: Text(
              v.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? AppColors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required bool active,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: TextButton.icon(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: active ? AppColors.accentBlue : AppColors.textMuted,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 30),
          ),
          icon: Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12.5)),
        ),
      ),
    );
  }

  // ---- status ------------------------------------------------------------

  Widget _statusStrip(int shown) {
    final (Color color, String label) = switch (_link) {
      ScannerLink.connected when _snap.streamConnected => (AppColors.profitGreen, 'LIVE'),
      ScannerLink.connected => (AppColors.warnAmber, 'DELAYED'),
      ScannerLink.connecting => (AppColors.warnAmber, 'CONNECTING'),
      ScannerLink.disconnected => (AppColors.lossRed, 'OFFLINE'),
    };
    final parts = <String>[
      if (_link != ScannerLink.connected)
        'Waiting for the local backend…'
      else ...[
        _snap.streamConnected
            ? 'Real-time trades (Yahoo stream, ${_snap.streamMessages} msgs)'
            : 'Price stream reconnecting - showing Finviz\'s delayed prices',
        if (_snap.session != 'unknown') 'session: ${_snap.session}',
        _snap.universeUpdated == null
            ? 'loading Finviz screens (~20s)…'
            : 'universe ${_snap.rows.length} stocks, Finviz ${_ago(_snap.universeUpdated!)}',
        'showing $shown',
      ],
    ];
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: AppColors.bgPrimary,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 7, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              parts.join('   ·   '),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        color: AppColors.warnAmber.withValues(alpha: 0.12),
        child: Text(text, style: const TextStyle(fontSize: 11.5, color: AppColors.warnAmber)),
      );

  static String _ago(DateTime t) {
    final s = DateTime.now().difference(t.toLocal()).inSeconds;
    if (s < 5) return 'just now';
    if (s < 60) return '${s}s ago';
    return '${s ~/ 60}m ago';
  }

  // ---- table -------------------------------------------------------------

  static const _cols = <(_Col, String, double, bool)>[
    // column, title, width (0 = flex), right-aligned
    (_Col.rank, '#', 34, true),
    (_Col.symbol, 'SYMBOL', 128, false),
    (_Col.price, 'PRICE', 82, true),
    (_Col.change, 'CHG %', 90, true),
    (_Col.gap, 'GAP %', 84, true),
    (_Col.volume, 'VOLUME', 80, true),
    (_Col.relVol, 'REL VOL', 74, true),
    (_Col.float, 'FLOAT', 72, true),
    (_Col.c1, '1M %', 64, true),
    (_Col.c5, '5M %', 64, true),
    (_Col.momo, 'MOMO', 96, false),
    (_Col.sector, 'SECTOR', 0, false),
  ];

  static const _colHelp = {
    _Col.change: 'Change vs previous close (live)',
    _Col.gap: 'Opening gap vs previous close',
    _Col.relVol: 'Volume vs a normal day at this time (live)',
    _Col.float: 'Shares available to trade (< 10M highlighted)',
    _Col.c1: 'Change over the last minute (live)',
    _Col.c5: 'Change over the last 5 minutes (live)',
    _Col.momo: 'Momentum 0-100: 5-min & 1-min change, rel. volume, day change',
  };

  Widget _table(List<ScannerRow> rows) {
    return Column(
      children: [
        Container(
          height: 28,
          decoration: const BoxDecoration(
            color: AppColors.bgSecondary,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(children: [for (final c in _cols) _headerCell(c)]),
        ),
        Expanded(child: rows.isEmpty ? _empty() : _list(rows)),
      ],
    );
  }

  Widget _headerCell((_Col, String, double, bool) c) {
    final (col, title, width, right) = c;
    final sorted = _sortCol == col;
    final text = Row(
      mainAxisAlignment: right ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.clip,
            softWrap: false,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
              color: sorted ? AppColors.accentBlue : AppColors.textMuted,
            ),
          ),
        ),
        if (sorted) Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 11, color: AppColors.accentBlue),
      ],
    );
    Widget cell = InkWell(
      onTap: col == _Col.rank
          ? null
          : () => setState(() {
                if (_sortCol == col) {
                  _sortAsc = !_sortAsc;
                } else {
                  _sortCol = col;
                  _sortAsc = col == _Col.symbol || col == _Col.sector || col == _Col.float;
                }
              }),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Align(alignment: right ? Alignment.centerRight : Alignment.centerLeft, child: text)),
    );
    final help = _colHelp[col];
    if (help != null) cell = Tooltip(message: help, waitDuration: const Duration(milliseconds: 400), child: cell);
    return width > 0 ? SizedBox(width: width, child: cell) : Expanded(child: cell);
  }

  Widget _empty() {
    final msg = switch (_link) {
      ScannerLink.connected when _snap.universeUpdated == null => 'Loading the Finviz screens… (first load takes ~20 seconds)',
      ScannerLink.connected => _snap.rows.isEmpty ? 'No stocks match the screens right now.' : 'No stocks match this view and filter.',
      _ => 'Connecting to the local backend…\nIf this persists, the backend (stockcalc_backend.exe) is not running.',
    };
    return Center(
      child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
    );
  }

  Widget _list(List<ScannerRow> rows) {
    final now = DateTime.now();
    return ListView.builder(
      itemCount: rows.length,
      itemExtent: _rowHeight,
      itemBuilder: (context, i) => _row(rows[i], i, now),
    );
  }

  Widget _row(ScannerRow r, int index, DateTime now) {
    final selected = r.symbol == _selected;
    final cells = <Widget>[];
    for (final c in _cols) {
      final (col, _, width, right) = c;
      final child = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Align(alignment: right ? Alignment.centerRight : Alignment.centerLeft, child: _cell(col, r, index, now)),
      );
      cells.add(width > 0 ? SizedBox(width: width, child: child) : Expanded(child: child));
    }
    return Material(
      color: selected
          ? AppColors.accentBlue.withValues(alpha: 0.22)
          : (index.isOdd ? AppColors.bgSecondary.withValues(alpha: 0.45) : AppColors.bgPrimary),
      child: InkWell(
        hoverColor: AppColors.bgHover.withValues(alpha: 0.6),
        onTap: () => setState(() => _selected = r.symbol),
        onDoubleTap: () => widget.onOpen(r),
        child: Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgSecondary))),
          child: Row(children: cells),
        ),
      ),
    );
  }

  static const _num = TextStyle(fontSize: 12.5, fontFamily: 'Consolas', color: AppColors.textPrimary);

  Widget _cell(_Col col, ScannerRow r, int index, DateTime now) {
    switch (col) {
      case _Col.rank:
        return Text('${index + 1}', style: _num.copyWith(color: AppColors.textMuted, fontSize: 11.5));
      case _Col.symbol:
        return Row(
          children: [
            Flexible(
              child: Text(
                r.symbol,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: 4),
            if (r.newHigh) _flag(Icons.bolt, AppColors.warnAmber, 'At the high of the day and rising'),
            if (r.relVolSpike) _flag(Icons.local_fire_department, AppColors.lossRed, 'Relative volume ≥ 5x'),
            if (r.lowFloat) _flag(Icons.diamond_outlined, AppColors.accentBlue, 'Low float (< 10M shares)'),
            if (r.highShort) _flag(Icons.warning_amber_rounded, AppColors.warnAmber, 'Short interest ≥ 20% of float'),
            if (!r.live) _flag(Icons.schedule, AppColors.textMuted, 'No trade seen yet - Finviz\'s delayed price'),
          ],
        );
      case _Col.price:
        return _flashing(r, now, Text(_price(r.price), style: _num));
      case _Col.change:
        return _heat(r.changePercent, 30, '${_signed(r.changePercent)}%');
      case _Col.gap:
        return _heat(r.gapPercent, 30, r.gapPercent == 0 ? '—' : '${_signed(r.gapPercent)}%');
      case _Col.volume:
        return Text(formatCompactVolume(r.volume), style: _num);
      case _Col.relVol:
        return _relVol(r.relVolume);
      case _Col.float:
        return Text(
          r.floatShares > 0 ? formatCompactVolume(r.floatShares) : '—',
          style: _num.copyWith(color: r.lowFloat ? AppColors.accentBlue : AppColors.textPrimary),
        );
      case _Col.c1:
        return _pct(r.change1m);
      case _Col.c5:
        return _pct(r.change5m);
      case _Col.momo:
        return _momo(r.momentum);
      case _Col.sector:
        return Text(
          r.sector,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        );
    }
  }

  Widget _flag(IconData icon, Color color, String tip) => Tooltip(
        message: tip,
        child: Padding(padding: const EdgeInsets.only(right: 2), child: Icon(icon, size: 13, color: color)),
      );

  /// Price cell that flashes green/red for a moment after each trade.
  Widget _flashing(ScannerRow r, DateTime now, Widget child) {
    final at = _flashAt[r.symbol];
    final remaining = at == null ? 0.0 : 1 - now.difference(at).inMilliseconds / _flashTime.inMilliseconds;
    if (remaining <= 0) return child;
    final color = switch (_flashDir[r.symbol]) {
      1 => AppColors.profitGreen,
      -1 => AppColors.lossRed,
      _ => AppColors.accentBlue,
    };
    return TweenAnimationBuilder<double>(
      key: ValueKey((r.symbol, at)),
      tween: Tween(begin: remaining, end: 0),
      duration: _flashTime * remaining,
      builder: (context, t, c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.55 * t), borderRadius: BorderRadius.circular(3)),
        child: c,
      ),
      child: child,
    );
  }

  /// Heat cell: green/red background scaled by magnitude (full at [full]).
  Widget _heat(double v, double full, String text) {
    final strength = (v.abs() / full).clamp(0.0, 1.0);
    final base = v >= 0 ? AppColors.profitGreen : AppColors.lossRed;
    return Container(
      width: double.infinity,
      height: _rowHeight - 6,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: v == 0 ? null : base.withValues(alpha: 0.18 + 0.67 * strength),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: _num.copyWith(
          fontWeight: FontWeight.bold,
          color: v == 0 ? AppColors.textMuted : (strength > 0.25 ? AppColors.white : base),
        ),
      ),
    );
  }

  Widget _relVol(double v) {
    final strength = ((v - 1) / 9).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: v >= 2 ? AppColors.accentBlue.withValues(alpha: 0.15 + 0.6 * strength) : null,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(v <= 0 ? '—' : '${v.toStringAsFixed(v >= 100 ? 0 : 1)}x', style: _num),
    );
  }

  Widget _pct(double v) => Text(
        v == 0 ? '—' : '${_signed(v)}%',
        style: _num.copyWith(color: v > 0 ? AppColors.profitGreen : (v < 0 ? AppColors.lossRed : AppColors.textMuted)),
      );

  Widget _momo(int score) {
    final color = score >= 70 ? AppColors.profitGreen : (score >= 40 ? AppColors.warnAmber : AppColors.textMuted);
    return Row(
      children: [
        SizedBox(width: 24, child: Text('$score', textAlign: TextAlign.right, style: _num.copyWith(color: color))),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 5,
              backgroundColor: AppColors.bgInput,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }

  static String _price(double p) => p <= 0 ? '—' : (p < 1 ? p.toStringAsFixed(4) : formatNumber(p));
  static String _signed(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(v.abs() >= 100 ? 0 : (v.abs() >= 10 ? 1 : 2))}';

  // ---- alerts ------------------------------------------------------------

  Widget _alertsPane() {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                const Text('ALERTS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                const Spacer(),
                if (_alerts.isNotEmpty)
                  InkWell(
                    onTap: () => setState(_alerts.clear),
                    child: const Text('Clear', style: TextStyle(fontSize: 11, color: AppColors.accentBlue)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _alerts.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Stocks that hit a new high with momentum, spike in volume, or jump into the top 10 gainers show up here.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: _alerts.length,
                    itemBuilder: (context, i) {
                      final a = _alerts[i];
                      final t = a.time;
                      final hh = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
                          '${t.second.toString().padLeft(2, '0')}';
                      return InkWell(
                        onTap: () => setState(() => _selected = a.symbol),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.bgPrimary))),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(a.symbol,
                                      style: const TextStyle(
                                          fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                  const SizedBox(width: 6),
                                  Text('${_signed(a.changePercent)}%',
                                      style: _num.copyWith(
                                          fontSize: 11.5,
                                          color: a.changePercent >= 0 ? AppColors.profitGreen : AppColors.lossRed)),
                                  const Spacer(),
                                  Text(hh, style: _num.copyWith(fontSize: 10.5, color: AppColors.textMuted)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text('${a.reason} @ ${_price(a.price)}',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ---- details -----------------------------------------------------------

  Widget _details(ScannerRow r) {
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(right: 18),
          child: RichText(
            text: TextSpan(children: [
              TextSpan(text: '$k ', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              TextSpan(text: v, style: _num.copyWith(fontSize: 12)),
            ]),
          ),
        );
    final lastTrade = r.lastTrade == null ? 'none yet' : _ago(r.lastTrade!);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r.symbol}  ·  ${r.name}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Wrap(
                  runSpacing: 2,
                  children: [
                    kv('Sector', [r.sector, r.industry].where((s) => s.isNotEmpty).join(' / ')),
                    kv('Country', r.country.isEmpty ? '—' : r.country),
                    kv('Mkt cap', r.marketCap > 0 ? formatCompactMarketCap(r.marketCap) : '—'),
                    kv('Prev close', _price(r.prevClose)),
                    kv('High', _price(r.high)),
                    kv('Avg vol', formatCompactVolume(r.avgVolume)),
                    kv('Short float', r.shortFloat > 0 ? '${r.shortFloat.toStringAsFixed(1)}%' : '—'),
                    kv('Last trade', lastTrade),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.https('finviz.com', '/quote.ashx', {'t': r.symbol})),
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('Finviz'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => widget.onOpen(r),
            icon: const Icon(Icons.calculate_outlined, size: 16),
            label: const Text('Open in Calculator'),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => setState(() => _selected = null),
            icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  // ---- filter dialog -----------------------------------------------------

  Future<void> _openFilter() async {
    final result = await showDialog<ScannerFilter>(
      context: context,
      builder: (context) => _FilterDialog(initial: _filter),
    );
    if (result != null) setState(() => _filter = result);
  }
}

class _FilterDialog extends StatefulWidget {
  final ScannerFilter initial;
  const _FilterDialog({required this.initial});

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late final _minPrice = _ctl(widget.initial.minPrice);
  late final _maxPrice = _ctl(widget.initial.maxPrice);
  late final _minRelVol = _ctl(widget.initial.minRelVolume);
  late final _maxFloat = _ctl(widget.initial.maxFloatMillions);
  late final _minVolK = _ctl(widget.initial.minVolume / 1000);
  late bool _liveOnly = widget.initial.liveOnly;

  static TextEditingController _ctl(double v) =>
      TextEditingController(text: v > 0 ? (v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v') : '');

  static double _val(TextEditingController c) => math.max(0, double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0);

  @override
  void dispose() {
    for (final c in [_minPrice, _maxPrice, _minRelVol, _maxFloat, _minVolK]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String label, TextEditingController c, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(width: 150, child: Text(label, style: const TextStyle(fontSize: 13))),
            Expanded(
              child: TextField(
                controller: c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(hintText: hint, isDense: true),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgSecondary,
      title: const Text('Scanner filter', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field('Min price (\$)', _minPrice, 'any'),
            _field('Max price (\$)', _maxPrice, 'any, e.g. 20'),
            _field('Min relative volume', _minRelVol, 'any, e.g. 5'),
            _field('Max float (M shares)', _maxFloat, 'any, e.g. 20'),
            _field('Min volume (K shares)', _minVolK, 'any, e.g. 500'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _liveOnly,
              onChanged: (v) => setState(() => _liveOnly = v ?? false),
              title: const Text('Only stocks with a live trade', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, const ScannerFilter()), child: const Text('Clear')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            ScannerFilter(
              minPrice: _val(_minPrice),
              maxPrice: _val(_maxPrice),
              minRelVolume: _val(_minRelVol),
              maxFloatMillions: _val(_maxFloat),
              minVolume: _val(_minVolK) * 1000,
              liveOnly: _liveOnly,
            ),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
