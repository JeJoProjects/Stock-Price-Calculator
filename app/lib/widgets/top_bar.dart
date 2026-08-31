import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Ported from Application::renderTopBar.
class TopBar extends StatelessWidget {
  final int tickerCount;
  const TopBar({super.key, required this.tickerCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.bgSecondary,
        border: Border(
          top: BorderSide(color: AppColors.accentBlue, width: 2),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          const Text('↗ StockCalc',
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 12),
          Flexible(
            child: Text('Realtime stock symbol search and profit planning',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
          const Spacer(),
          Text('$tickerCount symbols loaded',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}
