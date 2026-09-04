import 'package:flutter/material.dart';
import '../core/settings_service.dart';
import '../theme/app_theme.dart';
import 'dismissible_dialog.dart';

/// Ported from Application::renderPreferencesDialog, reorganized into tabs
/// (Appearance / Display / Finnhub) rather than one long scroll - a small
/// UX upgrade the immediate-mode ImGui version couldn't easily do.
/// Esc closes it (see dismissible_dialog.dart); every control also
/// participates in the default Tab focus order for keyboard-only use.
Future<AppSettings?> showPreferencesDialog(BuildContext context, AppSettings current) {
  return showAppDialog<AppSettings>(
    context,
    child: _PreferencesContent(initial: current),
  );
}

class _PreferencesContent extends StatefulWidget {
  final AppSettings initial;
  const _PreferencesContent({required this.initial});

  @override
  State<_PreferencesContent> createState() => _PreferencesContentState();
}

class _PreferencesContentState extends State<_PreferencesContent> {
  late double _fontSize = widget.initial.fontSize;
  late int _maxSearchResults = widget.initial.maxSearchResults;
  late bool _showExchangeBadges = widget.initial.showExchangeBadges;
  late bool _showStatsBar = widget.initial.showStatsBar;
  late int _screenerRefreshSeconds = widget.initial.screenerRefreshSeconds;

  void _apply() {
    Navigator.of(context).pop(AppSettings(
      fontSize: _fontSize,
      maxSearchResults: _maxSearchResults,
      showExchangeBadges: _showExchangeBadges,
      showStatsBar: _showStatsBar,
      screenerRefreshSeconds: _screenerRefreshSeconds,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: AppDialogShell(
        title: 'Preferences',
        width: 460,
        height: 400,
        child: Column(
          children: [
            const TabBar(
              labelColor: AppColors.accentBlue,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.accentBlue,
              tabs: [Tab(text: 'Appearance'), Tab(text: 'Display'), Tab(text: 'Finnhub')],
            ),
            Expanded(
              child: TabBarView(
                children: [_appearanceTab(), _displayTab(), _finnhubTab()],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _apply, child: const Text('Apply')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appearanceTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Font Size (${_fontSize.round()}px)',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          Slider(
            value: _fontSize,
            min: 10,
            max: 24,
            divisions: 14,
            onChanged: (v) => setState(() => _fontSize = v),
          ),
          const SizedBox(height: 16),
          Text('Max Search Results ($_maxSearchResults)',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          Slider(
            value: _maxSearchResults.toDouble(),
            min: 5,
            max: 25,
            divisions: 20,
            onChanged: (v) => setState(() => _maxSearchResults = v.round()),
          ),
        ],
      ),
    );
  }

  Widget _displayTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show Exchange Badges',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
            value: _showExchangeBadges,
            onChanged: (v) => setState(() => _showExchangeBadges = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show Stats Bar',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
            value: _showStatsBar,
            onChanged: (v) => setState(() => _showStatsBar = v),
          ),
          const SizedBox(height: 16),
          Text('Screener Refresh (${_formatRefreshInterval(_screenerRefreshSeconds)})',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          Slider(
            value: _screenerRefreshSeconds.toDouble(),
            min: 10,
            max: 300,
            divisions: 29,
            onChanged: (v) => setState(() => _screenerRefreshSeconds = v.round()),
          ),
          const Text(
            'How often the app re-checks the Finviz, Yahoo, and Combined '
            'screener tabs. The underlying data itself refreshes on the '
            'backend\'s own schedule (30s by default), so setting this below '
            'that just re-fetches the same cached snapshot sooner.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _formatRefreshInterval(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return remainder == 0 ? '${minutes}m' : '${minutes}m ${remainder}s';
  }

  Widget _finnhubTab() {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Text(
        'The Finnhub API key now lives on the backend server only '
        '(set FINNHUB_API_KEY before starting backend/bin/server.dart) - '
        'the app never sees or stores it, so there is nothing to configure '
        'here anymore. This also means one key serves every client instead '
        'of each install needing its own.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
      ),
    );
  }
}
