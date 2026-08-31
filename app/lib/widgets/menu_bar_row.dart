import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Ported from Application::renderMenuBar (File/Edit/View/Help), using
/// PopupMenuButton for a discoverable entry point to actions that also
/// have keyboard shortcuts - the shortcut labels double as a cheat sheet.
class MenuBarRow extends StatelessWidget {
  final VoidCallback onNewPanel;
  final VoidCallback onResetAll;
  final VoidCallback onQuit;
  final VoidCallback onPreferences;
  final VoidCallback onFocusSearch;
  final VoidCallback onAbout;
  final bool showStatsBar;
  final bool showExchangeBadges;
  final ValueChanged<bool> onToggleStatsBar;
  final ValueChanged<bool> onToggleExchangeBadges;

  const MenuBarRow({
    super.key,
    required this.onNewPanel,
    required this.onResetAll,
    required this.onQuit,
    required this.onPreferences,
    required this.onFocusSearch,
    required this.onAbout,
    required this.showStatsBar,
    required this.showExchangeBadges,
    required this.onToggleStatsBar,
    required this.onToggleExchangeBadges,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      color: AppColors.bgSecondary,
      child: Row(
        children: [
          _menu('File', [
            _item('New Panel', 'Ctrl+N', onNewPanel),
            _item('Reset All', 'Ctrl+R', onResetAll),
            const PopupMenuDivider(),
            _item('Quit', 'Ctrl+Q', onQuit),
          ]),
          _menu('Edit', [
            _item('Preferences', 'Ctrl+,', onPreferences),
            _item('Focus Search', 'Ctrl+F', onFocusSearch),
          ]),
          _menu('View', [
            _toggleItem('Show Stats Bar', showStatsBar, onToggleStatsBar),
            _toggleItem('Show Exchange Badges', showExchangeBadges, onToggleExchangeBadges),
          ]),
          _menu('Help', [
            _item('About', null, onAbout),
          ]),
        ],
      ),
    );
  }

  Widget _menu(String label, List<PopupMenuEntry<void>> items) {
    return PopupMenuButton<void>(
      tooltip: label,
      color: AppColors.bgSecondary,
      itemBuilder: (context) => items,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ),
      ),
    );
  }

  PopupMenuItem<void> _item(String label, String? shortcut, VoidCallback onTap) {
    return PopupMenuItem<void>(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          if (shortcut != null) ...[
            const SizedBox(width: 16),
            Text(shortcut, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  PopupMenuItem<void> _toggleItem(String label, bool value, ValueChanged<bool> onChanged) {
    return PopupMenuItem<void>(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          Icon(value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16, color: AppColors.accentBlue),
        ],
      ),
    );
  }
}
