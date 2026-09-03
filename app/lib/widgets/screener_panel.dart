import 'package:flutter/material.dart';
import '../core/formatting.dart';
import '../screener/screener_client.dart';
import '../screener/screener_models.dart';
import '../theme/app_theme.dart';

/// New feature (not in the old app): a live "unusual volume" movers list,
/// mirroring https://finviz.com/screener?v=111&s=ta_unusualvolume&o=-change
/// exactly - the backend's /screener/top endpoint is fed by parsing that
/// free Finviz page directly (see backend/lib/finviz_client.dart), not a
/// Finnhub approximation, so there's no market-cap ceiling here despite the
/// panel's name; it shows whatever that Finviz screen shows.
///
/// Status (gain/loss) is never color-alone here - every colored value pairs
/// with an up/down icon, per the app's own accessibility bar for status
/// encoding (see CombinedStatsBar / PurchasePanelCard for the same rule).
class ScreenerPanel extends StatefulWidget {
  final ScreenerClient client;
  final void Function(ScreenerRow row) onSelect;

  const ScreenerPanel({super.key, required this.client, required this.onSelect});

  @override
  State<ScreenerPanel> createState() => _ScreenerPanelState();
}

class _ScreenerPanelState extends State<ScreenerPanel> {
  ScreenerSnapshot _snapshot = const ScreenerSnapshot();
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    widget.client.snapshots.listen((s) {
      if (mounted) setState(() => _snapshot = s);
    });
    widget.client.start();
  }

  @override
  void dispose() {
    widget.client.stop();
    super.dispose();
  }

  bool get _isLive => _snapshot.error == null && _snapshot.lastUpdated != null;

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
          _header(),
          const Divider(height: 1, color: AppColors.border),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF232838), AppColors.bgSecondary],
        ),
        border: Border(top: BorderSide(color: AppColors.accentBlue, width: 2)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentBlue.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bolt_rounded, size: 16, color: AppColors.accentBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Micro-Cap Movers',
                    style: TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                Text(
                  'Live from Finviz • unusual volume',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          _liveBadge(),
        ],
      ),
    );
  }

  Widget _liveBadge() {
    final label =
        _isLive ? _relativeTime(_snapshot.lastUpdated!) : (_snapshot.error != null ? 'Error' : '—');
    final dotColor = _isLive ? AppColors.profitGreen : AppColors.textMuted;
    return Column(
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
            Text(_isLive ? 'LIVE' : 'IDLE',
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
    );
  }

  Widget _body() {
    if (_snapshot.error != null) {
      return _emptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Can\'t reach the backend',
        subtitle: _snapshot.error!,
        iconColor: AppColors.lossRed,
      );
    }
    if (_snapshot.rows.isEmpty) {
      return _emptyState(
        icon: Icons.search_off_rounded,
        title: 'No movers right now',
        subtitle: 'Finviz isn\'t showing any unusual-volume movers at the moment.',
        iconColor: AppColors.textMuted,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _snapshot.rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border, indent: 16),
      itemBuilder: (context, i) => _row(i, _snapshot.rows[i]),
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

  Widget _sectorChip(String sector) =>
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 110), child: _chip(sector));

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

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
