import 'package:flutter/material.dart';
import '../core/formatting.dart';
import '../screener/screener_client.dart';
import '../screener/screener_models.dart';
import '../theme/app_theme.dart';

/// New feature (not in the old app): a live micro-cap / unusual-move
/// screener, replicating the Finviz "unusual volume" view the user wants
/// (market cap < $500M, large % move), backed by the Dart server's
/// /screener/top endpoint rather than scraping Finviz directly.
class ScreenerPanel extends StatefulWidget {
  final ScreenerClient client;
  final void Function(ScreenerRow row) onSelect;

  const ScreenerPanel({super.key, required this.client, required this.onSelect});

  @override
  State<ScreenerPanel> createState() => _ScreenerPanelState();
}

class _ScreenerPanelState extends State<ScreenerPanel> {
  ScreenerSnapshot _snapshot = const ScreenerSnapshot();

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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Micro-Cap Movers',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                ),
                if (_snapshot.lastUpdated != null)
                  Text(_relativeTime(_snapshot.lastUpdated!),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          if (_snapshot.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_snapshot.error!,
                  style: const TextStyle(color: AppColors.lossRed, fontSize: 12)),
            )
          else if (_snapshot.rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No movers matching criteria yet.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _snapshot.rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, i) => _row(_snapshot.rows[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(ScreenerRow row) {
    final positive = row.changePercent >= 0;
    final color = positive ? AppColors.profitGreen : AppColors.lossRed;
    return InkWell(
      onTap: () => widget.onSelect(row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.symbol,
                      style: const TextStyle(
                          color: AppColors.white, fontFamily: 'Consolas', fontWeight: FontWeight.bold)),
                  Text(row.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  Text('Cap ${formatCompactMarketCap(row.marketCap)}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatCurrency(row.price),
                    style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Consolas')),
                Text('${positive ? '+' : ''}${row.changePercent.toStringAsFixed(2)}%',
                    style: TextStyle(color: color, fontFamily: 'Consolas', fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
