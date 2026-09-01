import 'package:flutter/material.dart';
import '../core/calc_engine.dart';
import '../core/formatting.dart';
import '../theme/app_theme.dart';

/// Ported from Application::renderCombinedStatsBar. Visibility is controlled
/// purely by the user's "Show Stats Bar" preference (not gated on having a
/// valid panel - see main.dart), so it renders correctly even with all
/// figures at zero.
class CombinedStatsBar extends StatelessWidget {
  final CombinedResult combined;
  final VoidCallback onResetAll;

  const CombinedStatsBar({super.key, required this.combined, required this.onResetAll});

  Color _profitColor(double v) {
    if (v.abs() < 0.005) return AppColors.textMuted;
    return v > 0 ? AppColors.profitGreen : AppColors.lossRed;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Scrolls horizontally rather than overflowing at narrow widths -
          // this bar is always visible now (not gated on having a valid
          // panel), so it needs to hold up at any window size.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _stat('Avg Price', formatCurrency(combined.avgSharePrice), AppColors.textPrimary),
                  const SizedBox(width: 32),
                  _stat('Total Investment', formatCurrency(combined.totalInvestment),
                      AppColors.textPrimary),
                  const SizedBox(width: 32),
                  _stat('Total Shares', formatNumber(combined.totalShares, decimals: 0),
                      AppColors.textPrimary),
                  const SizedBox(width: 32),
                  _stat('Total Profit', formatProfit(combined.totalProfit),
                      _profitColor(combined.totalProfit)),
                  const SizedBox(width: 32),
                  _stat('Avg Profit', formatProfit(combined.avgProfit),
                      _profitColor(combined.avgProfit)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 100,
            height: 36,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.lossRed,
                side: const BorderSide(color: AppColors.lossRed),
              ),
              onPressed: onResetAll,
              child: const Text('Reset All'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        Text(value,
            style: TextStyle(
                color: color, fontFamily: 'Consolas', fontWeight: FontWeight.bold, fontSize: 15)),
      ],
    );
  }
}
