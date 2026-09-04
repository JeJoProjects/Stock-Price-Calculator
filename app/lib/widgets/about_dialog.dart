import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'dismissible_dialog.dart';

/// Ported from Application::renderAboutDialog.
void showStockCalcAboutDialog(BuildContext context) {
  showAppDialog(
    context,
    child: AppDialogShell(
      title: 'About',
      width: 380,
      height: 220,
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Stock Screener',
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 4),
            Text('Version 3.0 | Flutter / Dart Edition',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            SizedBox(height: 16),
            Text(
              'A stock investment profit calculator with a live Finviz/Yahoo '
              'movers screener.',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 16),
            Text('Built with Flutter + Dart',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            Text('TradingView-inspired dark theme',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
        ),
      ),
    ),
  );
}
