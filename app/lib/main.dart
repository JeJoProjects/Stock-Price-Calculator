import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'core/calc_engine.dart';
import 'core/formatting.dart';
import 'core/panel_state.dart';
import 'core/settings_service.dart';
import 'market/market_client.dart';
import 'search/search_engine.dart';
import 'search/ticker_data.dart';
import 'screener/screener_client.dart';
import 'screener/screener_models.dart';
import 'theme/app_theme.dart';
import 'widgets/about_dialog.dart';
import 'widgets/chart_pane.dart';
import 'widgets/combined_stats_bar.dart';
import 'widgets/menu_bar_row.dart';
import 'widgets/new_purchase_card.dart';
import 'widgets/preferences_dialog.dart';
import 'widgets/purchase_panel_card.dart';
import 'widgets/screener_panel.dart';
import 'widgets/search_bar_section.dart';
import 'widgets/top_bar.dart';

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    final settings = await SettingsService().load();
    final windowOptions = WindowOptions(
      size: Size(settings.windowWidth, settings.windowHeight),
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (settings.windowX != null && settings.windowY != null) {
        await windowManager.setPosition(Offset(settings.windowX!, settings.windowY!));
      } else {
        await windowManager.center();
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const StockCalcApp());
}

class StockCalcApp extends StatelessWidget {
  const StockCalcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StockCalc',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WindowListener {
  final List<PanelState> _panels = [];
  List<PanelResult> _results = [];
  CombinedResult _combined = const CombinedResult();
  int _nextPanelId = 1;
  SearchEngine? _searchEngine;
  final _searchFocusNode = FocusNode();
  final _screenerClient = ScreenerClient();
  final _marketClient = MarketDataService();
  final _settingsService = SettingsService();
  AppSettings _settings = AppSettings();
  String? _chartSymbol;
  String _chartCompany = '';
  String _chartExchange = '';
  Timer? _windowSaveDebounce;

  @override
  void initState() {
    super.initState();
    _addPanel();
    _loadSearchEngine();
    if (_isDesktop) windowManager.addListener(this);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.load();
    setState(() => _settings = settings);
  }

  /// Ported from main.cpp's saveSettings-on-shutdown, but continuous
  /// (debounced) rather than only-on-clean-exit, using window_manager's
  /// resize/move events instead of a final glfwGetWindowPos/Size read.
  void _scheduleWindowGeometrySave() {
    _windowSaveDebounce?.cancel();
    _windowSaveDebounce = Timer(const Duration(milliseconds: 400), () async {
      final bounds = await windowManager.getBounds();
      // Keep the in-memory settings object in sync too - otherwise a later
      // full save() from an unrelated preference change (e.g. toggling a
      // View menu checkbox) would overwrite these keys with stale values.
      _settings.windowWidth = bounds.width;
      _settings.windowHeight = bounds.height;
      _settings.windowX = bounds.left;
      _settings.windowY = bounds.top;
      await _settingsService.saveWindowGeometry(
        bounds.width,
        bounds.height,
        bounds.left,
        bounds.top,
      );
    });
  }

  @override
  void onWindowResized() => _scheduleWindowGeometrySave();

  @override
  void onWindowMoved() => _scheduleWindowGeometrySave();

  Future<void> _openPreferences() async {
    final result = await showPreferencesDialog(context, _settings);
    if (result != null) {
      setState(() => _settings = result);
      await _settingsService.save(result);
    }
  }

  /// Same idea as _applySearchResult, but from a screener row: also seeds
  /// the share price since the screener already knows the current quote.
  void _applyScreenerRow(ScreenerRow row) {
    setState(() {
      _panels.add(PanelState(id: _nextPanelId++, displayIndex: _panels.length));
      final panel = _panels.last;
      panel.tickerSymbol = row.symbol;
      panel.companyName = row.name;
      panel.exchange = row.exchange;
      panel.matchPreview = 'From micro-cap screener';
      panel.priceText = row.price.toStringAsFixed(2);
      panel.updateFieldTracking(2);
      _recalculateAll();
      _chartSymbol = row.symbol;
      _chartCompany = row.name;
      _chartExchange = row.exchange;
    });
  }

  Future<void> _loadSearchEngine() async {
    final tickers = await loadTickerUniverse();
    setState(() => _searchEngine = SearchEngine(tickers));
  }

  /// Ported from Application::applySearchResult (application.cpp:1312-1321).
  void _applySearchResult(TickerEntry entry, String preview) {
    setState(() {
      if (_panels.isEmpty) _panels.add(PanelState(id: _nextPanelId++, displayIndex: 0));
      final panel = _panels.last;
      panel.tickerSymbol = entry.symbol;
      panel.companyName = entry.name;
      panel.exchange = entry.exchange;
      panel.matchPreview = preview.isEmpty ? 'Selected from search' : preview;
      _chartSymbol = entry.symbol;
      _chartCompany = entry.name;
      _chartExchange = entry.exchange;
    });
  }

  void _addPanel() {
    setState(() {
      _panels.add(PanelState(id: _nextPanelId++, displayIndex: _panels.length));
      _recalculateAll();
    });
  }

  void _removePanel(int index) {
    setState(() {
      _panels.removeAt(index);
      for (var i = 0; i < _panels.length; i++) {
        _panels[i].displayIndex = i;
      }
      _recalculateAll();
    });
  }

  void _resetAll() {
    setState(() {
      _panels.clear();
      _nextPanelId = 1;
      _panels.add(PanelState(id: _nextPanelId++, displayIndex: 0));
      _recalculateAll();
    });
  }

  void _onFieldChanged(int panelIndex, int fieldId, String text) {
    final panel = _panels[panelIndex];
    switch (fieldId) {
      case 1:
        panel.investmentText = text;
      case 2:
        panel.priceText = text;
      case 3:
        panel.sharesText = text;
      case 4:
        panel.targetText = text;
    }
    panel.updateFieldTracking(fieldId);
    setState(_recalculateAll);
  }

  /// Ported from Application::recalculateAll (application.cpp:1273-1299):
  /// rebuilds each panel's result from its parsed fields + change history,
  /// then writes any inferred value back into the text field.
  void _recalculateAll() {
    final results = <PanelResult>[];
    for (final panel in _panels) {
      final input = PanelInput(
        totalInvestment: panel.investmentValue,
        sharePrice: panel.priceValue,
        totalShares: panel.sharesValue,
        targetPrice: panel.targetValue,
        lastChanged: panel.lastChanged,
        secondLastChanged: panel.secondLastChanged,
      );
      final result = calculatePanel(input);
      results.add(result);

      switch (result.inferredField) {
        case 1:
          panel.investmentText = formatValue(result.totalInvestment);
        case 2:
          panel.priceText = formatValue(result.sharePrice);
        case 3:
          panel.sharesText = formatValue(result.totalShares);
      }
    }
    _results = results;
    _combined = calculateCombined(results);
  }

  @override
  Widget build(BuildContext context) {
    // Font-size preference scales all text app-wide, matching the old
    // app's fontSize-driven ImGui rebuild but via Flutter's built-in
    // text scaler instead of reloading font atlases.
    final textScale = _settings.fontSize / 15.0;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Focus(
      autofocus: true,
      onKeyEvent: _handleShortcuts,
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: Column(
          children: [
            MenuBarRow(
              onNewPanel: _addPanel,
              onResetAll: _resetAll,
              onQuit: () => SystemNavigator.pop(),
              onPreferences: _openPreferences,
              onFocusSearch: () => _searchFocusNode.requestFocus(),
              onAbout: () => showStockCalcAboutDialog(context),
              showStatsBar: _settings.showStatsBar,
              showExchangeBadges: _settings.showExchangeBadges,
              onToggleStatsBar: (v) {
                setState(() => _settings.showStatsBar = v);
                _settingsService.save(_settings);
              },
              onToggleExchangeBadges: (v) {
                setState(() => _settings.showExchangeBadges = v);
                _settingsService.save(_settings);
              },
            ),
            TopBar(tickerCount: _searchEngine?.tickerCount ?? 0),
            if (_searchEngine != null)
              SearchBarSection(
                engine: _searchEngine!,
                onSelect: _applySearchResult,
                focusNode: _searchFocusNode,
                maxResults: _settings.maxSearchResults,
                showExchangeBadges: _settings.showExchangeBadges,
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(kPanelSpacing),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Centered, wrapping layout: with few panels the group
                    // sits in the visual middle of the area (reads as
                    // intentional) rather than pinned top-left with a huge
                    // empty area below; with many panels it flows into
                    // additional rows, filling both width and height.
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight),
                            child: Center(
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                runAlignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: kPanelSpacing,
                                runSpacing: kPanelSpacing,
                                children: [
                                  for (var i = 0; i < _panels.length; i++)
                                    PurchasePanelCard(
                                      key: ValueKey(_panels[i].id),
                                      panel: _panels[i],
                                      result: _results[i],
                                      canDelete: _panels.length > 1,
                                      onFieldChanged: (fieldId, text) =>
                                          _onFieldChanged(i, fieldId, text),
                                      onReset: () => setState(() {
                                        _panels[i].reset();
                                        _recalculateAll();
                                      }),
                                      onDelete: () => _removePanel(i),
                                    ),
                                  NewPurchaseCard(onTap: _addPanel),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 340,
                      margin: const EdgeInsets.only(left: kPanelSpacing),
                      child: Column(
                        children: [
                          // Market View gets the larger share of the column.
                          Expanded(
                            flex: 2,
                            child: ChartPane(
                              symbol: _chartSymbol,
                              companyName: _chartCompany,
                              exchange: _chartExchange,
                              client: _marketClient,
                            ),
                          ),
                          const SizedBox(height: kPanelSpacing),
                          Expanded(
                            flex: 1,
                            child: ScreenerPanel(client: _screenerClient, onSelect: _applyScreenerRow),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Shown purely based on the user's preference now, not gated on
            // having a valid panel - a toggled-on bar that silently stays
            // hidden until you fill in numbers reads as broken.
            if (_settings.showStatsBar)
              CombinedStatsBar(combined: _combined, onResetAll: _resetAll),
          ],
        ),
      ),
      ),
    );
  }

  /// Ported from Application::handleShortcuts (application.cpp:1301-1310).
  KeyEventResult _handleShortcuts(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    if (!isCtrl) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.keyN) {
      _addPanel();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyR) {
      _resetAll();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyQ) {
      SystemNavigator.pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.comma) {
      _openPreferences();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    _windowSaveDebounce?.cancel();
    _searchFocusNode.dispose();
    _screenerClient.dispose();
    _marketClient.close();
    super.dispose();
  }
}
