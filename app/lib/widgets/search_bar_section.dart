import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../search/online_search_client.dart';
import '../search/search_engine.dart';
import '../search/ticker_data.dart';
import '../theme/app_theme.dart';

/// Ported from Application::renderSearchBar / renderSearchDropdown, plus
/// the online (Yahoo-bridge) merge from Application::mergeOnlineResults -
/// now hitting the Dart backend's /search endpoint instead of shelling out
/// to a hardcoded python.exe path.
class SearchBarSection extends StatefulWidget {
  final SearchEngine engine;
  final int maxResults;
  final bool showExchangeBadges;
  final void Function(TickerEntry entry, String preview) onSelect;
  final FocusNode? focusNode;
  final OnlineSearchClient? onlineClient;

  const SearchBarSection({
    super.key,
    required this.engine,
    required this.onSelect,
    this.maxResults = 12,
    this.showExchangeBadges = true,
    this.focusNode,
    this.onlineClient,
  });

  @override
  State<SearchBarSection> createState() => _SearchBarSectionState();
}

class _SearchBarSectionState extends State<SearchBarSection> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  late final OnlineSearchClient _onlineClient = widget.onlineClient ?? OnlineSearchClient();
  List<SearchResult> _offlineResults = [];
  List<SearchResult> _results = [];
  int _selectedIndex = 0;
  bool _dropdownOpen = false;
  Timer? _onlineDebounce;
  int _requestId = 0;

  void _runSearch(String text) {
    _requestId++;
    final requestId = _requestId;
    final results = widget.engine.search(text, maxResults: widget.maxResults);
    setState(() {
      _offlineResults = results;
      _results = results;
      _dropdownOpen = results.isNotEmpty;
      _selectedIndex = 0;
    });

    _onlineDebounce?.cancel();
    if (text.trim().length < 2) return;
    // Debounced 0.18s idle, same as the old app's dispatchPendingOnlineSearch.
    _onlineDebounce = Timer(const Duration(milliseconds: 180), () async {
      final online = await _onlineClient.search(text, maxResults: widget.maxResults);
      if (!mounted || requestId != _requestId || online.isEmpty) return;
      setState(() {
        _results = mergeOnlineResults(_offlineResults, online, maxResults: widget.maxResults);
        _dropdownOpen = _results.isNotEmpty;
      });
    });
  }

  void _clear() {
    _onlineDebounce?.cancel();
    _requestId++;
    _controller.clear();
    setState(() {
      _offlineResults = [];
      _results = [];
      _dropdownOpen = false;
    });
    _focusNode.requestFocus();
  }

  void _select(int index) {
    if (index < 0 || index >= _results.length) return;
    final r = _results[index];
    widget.onSelect(r.entry, r.preview);
    _controller.clear();
    setState(() {
      _results = [];
      _dropdownOpen = false;
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_dropdownOpen || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _selectedIndex = (_selectedIndex + 1).clamp(0, _results.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _selectedIndex = (_selectedIndex - 1).clamp(0, _results.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _select(_selectedIndex);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _dropdownOpen = false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _onlineDebounce?.cancel();
    if (widget.onlineClient == null) _onlineClient.close();
    _controller.dispose();
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.bgPrimary,
          child: Focus(
            onKeyEvent: _handleKey,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search symbol or company name...',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 18),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
                        onPressed: _clear,
                      )
                    : null,
              ),
              onChanged: _runSearch,
            ),
          ),
        ),
        if (_dropdownOpen) _buildDropdown(),
      ],
    );
  }

  Widget _buildDropdown() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 340),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final r = _results[i];
                final selected = i == _selectedIndex;
                return InkWell(
                  onTap: () => _select(i),
                  onHover: (hovering) {
                    if (hovering) setState(() => _selectedIndex = i);
                  },
                  child: Container(
                    color: selected ? AppColors.accentBlue.withValues(alpha: 0.16) : null,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 72,
                          child: Text(r.entry.symbol,
                              style: const TextStyle(
                                  color: AppColors.white,
                                  fontFamily: 'Consolas',
                                  fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.entry.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                              Text(r.preview,
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                        if (widget.showExchangeBadges)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.bgInput,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(r.entry.exchange,
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: const Text('↑↓ navigate • Enter select • Esc close',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
          ),
        ],
      ),
    );
  }
}
