/// Ported from src/config/settingsManager.hpp/.cpp, using shared_preferences
/// instead of a hand-rolled JSON file. Same field names/defaults as the old
/// stockcalc_settings.json schema (minus the Finnhub key, which now lives on
/// the backend only - see migration plan's Settings section).
library;

import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  double fontSize;
  int maxSearchResults;
  bool showExchangeBadges;
  bool showStatsBar;
  int screenerRefreshSeconds;
  double screenerPanelWidth;
  double windowWidth;
  double windowHeight;
  double? windowX;
  double? windowY;

  AppSettings({
    this.fontSize = 15.0,
    this.maxSearchResults = 12,
    this.showExchangeBadges = true,
    this.showStatsBar = true,
    this.screenerRefreshSeconds = 30,
    this.screenerPanelWidth = 400,
    this.windowWidth = 1600,
    this.windowHeight = 900,
    this.windowX,
    this.windowY,
  });
}

class SettingsService {
  static const _kFontSize = 'fontSize';
  static const _kMaxSearchResults = 'maxSearchResults';
  static const _kShowExchangeBadges = 'showExchangeBadges';
  static const _kShowStatsBar = 'showStatsBar';
  static const _kScreenerRefreshSeconds = 'screenerRefreshSeconds';
  static const _kScreenerPanelWidth = 'screenerPanelWidth';
  static const _kWindowWidth = 'windowWidth';
  static const _kWindowHeight = 'windowHeight';
  static const _kWindowX = 'windowX';
  static const _kWindowY = 'windowY';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      fontSize: prefs.getDouble(_kFontSize) ?? 15.0,
      maxSearchResults: prefs.getInt(_kMaxSearchResults) ?? 12,
      showExchangeBadges: prefs.getBool(_kShowExchangeBadges) ?? true,
      showStatsBar: prefs.getBool(_kShowStatsBar) ?? true,
      screenerRefreshSeconds: prefs.getInt(_kScreenerRefreshSeconds) ?? 30,
      screenerPanelWidth: prefs.getDouble(_kScreenerPanelWidth) ?? 400,
      windowWidth: prefs.getDouble(_kWindowWidth) ?? 1600,
      windowHeight: prefs.getDouble(_kWindowHeight) ?? 900,
      windowX: prefs.getDouble(_kWindowX),
      windowY: prefs.getDouble(_kWindowY),
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kFontSize, settings.fontSize);
    await prefs.setInt(_kMaxSearchResults, settings.maxSearchResults);
    await prefs.setBool(_kShowExchangeBadges, settings.showExchangeBadges);
    await prefs.setBool(_kShowStatsBar, settings.showStatsBar);
    await prefs.setInt(_kScreenerRefreshSeconds, settings.screenerRefreshSeconds);
    await prefs.setDouble(_kScreenerPanelWidth, settings.screenerPanelWidth);
    await prefs.setDouble(_kWindowWidth, settings.windowWidth);
    await prefs.setDouble(_kWindowHeight, settings.windowHeight);
    if (settings.windowX != null) await prefs.setDouble(_kWindowX, settings.windowX!);
    if (settings.windowY != null) await prefs.setDouble(_kWindowY, settings.windowY!);
  }

  /// Saves only window geometry, without disturbing other settings already
  /// in memory elsewhere (called frequently on resize/move, debounced by
  /// the caller).
  Future<void> saveWindowGeometry(double width, double height, double x, double y) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kWindowWidth, width);
    await prefs.setDouble(_kWindowHeight, height);
    await prefs.setDouble(_kWindowX, x);
    await prefs.setDouble(_kWindowY, y);
  }
}
