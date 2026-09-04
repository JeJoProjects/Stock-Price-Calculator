import 'dart:async';
import 'package:flutter/material.dart';
import '../core/formatting.dart';
import '../screener/screener_client.dart';
import '../screener/screener_filters.dart';
import '../screener/screener_hub.dart';
import '../screener/screener_models.dart';
import '../theme/app_theme.dart';

/// A live movers screener with three tabs - Finviz, Yahoo, and a Combined
/// view of symbols appearing on both - each independently polling its own
/// backend endpoint (see ScreenerHub) but sharing one filter bar and one
/// status/countdown/refresh strip that always reflects the active tab.
///
/// Status (gain/loss) is never color-alone here - every colored value pairs
/// with an up/down icon, per the app's own accessibility bar for status
/// encoding (see CombinedStatsBar / PurchasePanelCard for the same rule).
class ScreenerPanel extends StatefulWidget {
  final ScreenerHub hub;
  final void Function(ScreenerRow row) onSelect;

  const ScreenerPanel({super.key, required this.hub, required this.onSelect});

  @override
  State<ScreenerPanel> createState() => _ScreenerPanelState();
}

class _ScreenerPanelState extends State<ScreenerPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 3, vsync: this)..addListener(() => setState(() {}));

  ScreenerSnapshot _finvizSnapshot = const ScreenerSnapshot();
  ScreenerSnapshot _yahooSnapshot = const ScreenerSnapshot();
  ScreenerSnapshot _combinedSnapshot = const ScreenerSnapshot();
  final List<StreamSubscription<ScreenerSnapshot>> _subscriptions = [];

  ScreenerFilters _filters = const ScreenerFilters();
  int? _hoveredIndex;
  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();
    _subscriptions.add(widget.hub.finviz.snapshots.listen((s) {
      if (mounted) setState(() => _finvizSnapshot = s);
    }));
    _subscriptions.add(widget.hub.yahoo.snapshots.listen((s) {
      if (mounted) setState(() => _yahooSnapshot = s);
    }));
    _subscriptions.add(widget.hub.combined.snapshots.listen((s) {
      if (mounted) setState(() => _combinedSnapshot = s);
    }));
    widget.hub.finviz.start();
    widget.hub.yahoo.start();
    widget.hub.combined.start();
    // Ticks purely to refresh the countdown label each second - the
    // snapshots themselves only change on an actual fetch.
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    widget.hub.finviz.stop();
    widget.hub.yahoo.stop();
    widget.hub.combined.stop();
    _countdownTicker?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  ScreenerSnapshot get _activeSnapshot =>
      [_finvizSnapshot, _yahooSnapshot, _combinedSnapshot][_tabController.index];
  ScreenerClient get _activeClient =>
      [widget.hub.finviz, widget.hub.yahoo, widget.hub.combined][_tabController.index];
  bool get _activeIsLive => _activeSnapshot.error == null && _activeSnapshot.lastUpdated != null;

  /// One button refreshes every tab, not just the active one - Combined is
  /// itself derived from Finviz+Yahoo's cached results, so refreshing all
  /// three together is what actually gets a fresher Combined view too.
  void _refreshAllNow() {
    widget.hub.finviz.refreshNow();
    widget.hub.yahoo.refreshNow();
    widget.hub.combined.refreshNow();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tabBar(),
          const Divider(height: 1, color: AppColors.border),
          _toolbarRow(),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _body(_finvizSnapshot),
                _body(_yahooSnapshot),
                _body(_combinedSnapshot),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF232838), AppColors.bgSecondary],
        ),
        border: Border(top: BorderSide(color: AppColors.accentBlue, width: 2)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.accentBlue,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.accentBlue,
        labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
        tabs: const [Tab(text: 'Finviz'), Tab(text: 'Yahoo'), Tab(text: 'Combined')],
      ),
    );
  }

  Widget _toolbarRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _presetDropdown(
                    label: 'Chg',
                    value: _filters.minChangePercent,
                    items: <double, String>{0: 'Any', 5: '5%+', 10: '10%+', 20: '20%+', 50: '50%+'},
                    onChanged: (v) => setState(() => _filters = _filters.copyWith(minChangePercent: v)),
                  ),
                  const SizedBox(width: 6),
                  _presetDropdown(
                    label: 'Vol',
                    value: _filters.minVolume,
                    items: <double, String>{
                      0: 'Any',
                      100000: '100K+',
                      500000: '500K+',
                      1000000: '1M+',
                      5000000: '5M+',
                    },
                    onChanged: (v) => setState(() => _filters = _filters.copyWith(minVolume: v)),
                  ),
                  const SizedBox(width: 6),
                  _presetDropdown(
                    label: 'Cap',
                    value: _filters.minMarketCap,
                    items: <double, String>{0: 'Any', 50e6: '50M+', 300e6: '300M+', 2e9: '2B+', 10e9: '10B+'},
                    onChanged: (v) => setState(() => _filters = _filters.copyWith(minMarketCap: v)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _statusArea(),
        ],
      ),
    );
  }

  Widget _presetDropdown({
    required String label,
    required double value,
    required Map<double, String> items,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: AppColors.bgInput, borderRadius: BorderRadius.circular(6)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<double>(
          value: value,
          isDense: true,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
          dropdownColor: AppColors.bgSecondary,
          icon: const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textMuted),
          items: [
            for (final entry in items.entries)
              DropdownMenuItem(value: entry.key, child: Text('$label ${entry.value}')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  /// The countdown-to-next-refresh + manual refresh button, in the same
  /// top-right slot the original mockup marks for its "Refresh Button" -
  /// always describing whichever tab is currently active.
  Widget _statusArea() {
    final String label;
    if (_activeSnapshot.error != null) {
      label = 'error';
    } else if (_activeSnapshot.lastUpdated == null) {
      label = '—';
    } else {
      final next = _activeSnapshot.lastUpdated!.add(_activeClient.pollInterval);
      final remaining = next.difference(DateTime.now());
      label = remaining.isNegative ? 'now' : 'next ${remaining.inSeconds}s';
    }
    final dotColor = _activeIsLive ? AppColors.profitGreen : AppColors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(_activeIsLive ? 'LIVE' : 'IDLE',
                    style: TextStyle(
                        color: dotColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6)),
              ],
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 9.5)),
          ],
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.textMuted),
          tooltip: 'Refresh Finviz, Yahoo & Combined now',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          onPressed: _refreshAllNow,
        ),
      ],
    );
  }

  Widget _body(ScreenerSnapshot snapshot) {
    if (snapshot.error != null) {
      return _emptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Can\'t reach the backend',
        subtitle: snapshot.error!,
        iconColor: AppColors.lossRed,
      );
    }
    if (snapshot.rows.isEmpty) {
      return _emptyState(
        icon: Icons.search_off_rounded,
        title: 'No movers right now',
        subtitle: 'This source isn\'t showing any movers at the moment.',
        iconColor: AppColors.textMuted,
      );
    }
    final rows = _filters.apply(snapshot.rows);
    if (rows.isEmpty) {
      return _emptyState(
        icon: Icons.filter_alt_off_rounded,
        title: 'No matches',
        subtitle: 'Nothing in this list passes the current filters.',
        iconColor: AppColors.textMuted,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border, indent: 16),
      itemBuilder: (context, i) => _row(i, rows[i]),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
  }) {
    // Scrollable-centered-content pattern: centers when there's room, scrolls
    // instead of overflowing when the panel is squeezed very short.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: _emptyStateContent(icon, title, subtitle, iconColor)),
        ),
      ),
    );
  }

  Widget _emptyStateContent(IconData icon, String title, String subtitle, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.4)),
          ],
        ),
      );
  }

  Widget _row(int index, ScreenerRow row) {
    final positive = row.changePercent >= 0;
    final statusColor = positive ? AppColors.profitGreen : AppColors.lossRed;
    final hovered = _hoveredIndex == index;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onSelect(row),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: hovered ? AppColors.accentBlue.withValues(alpha: 0.08) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rankBadge(index + 1),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(row.symbol,
                            style: const TextStyle(
                                color: AppColors.white,
                                fontFamily: 'Consolas',
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        if (row.exchange.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(row.exchange,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 9.5)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(row.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (row.marketCap > 0) _capChip(row.marketCap),
                        _volumeChip(row.volume),
                        if (row.sector.isNotEmpty) _sectorChip(row.sector),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatCurrency(row.price),
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontFamily: 'Consolas', fontSize: 12.5)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          positive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          size: 11,
                          color: statusColor,
                        ),
                        const SizedBox(width: 2),
                        Text('${row.changePercent.abs().toStringAsFixed(2)}%',
                            style: TextStyle(
                                color: statusColor,
                                fontFamily: 'Consolas',
                                fontWeight: FontWeight.bold,
                                fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rankBadge(int rank) {
    // Top 3 get a subtle accent treatment so the ranking reads at a glance,
    // matching the app's existing accent-blue-for-emphasis convention.
    final isTopThree = rank <= 3;
    return Container(
      width: 20,
      height: 20,
      margin: const EdgeInsets.only(top: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isTopThree ? AppColors.accentBlue.withValues(alpha: 0.18) : AppColors.bgInput,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$rank',
          style: TextStyle(
              color: isTopThree ? AppColors.accentBlue : AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _capChip(double marketCap) => _chip('Cap ${formatCompactMarketCap(marketCap)}');

  Widget _volumeChip(double volume) => _chip('Vol ${formatCompactVolume(volume)}');

  // No fixed max width here (unlike the old single-column layout) - the
  // panel is now user-resizable, so the sector chip should be free to use
  // whatever room is available instead of eliding early; Wrap already
  // drops it to the next line if a row gets tight.
  Widget _sectorChip(String sector) => _chip(sector);

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.bgInput,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 9.5)),
    );
  }
}
