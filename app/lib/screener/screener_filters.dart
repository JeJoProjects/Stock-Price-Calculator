/// A small, deliberately limited Finviz-style filter set (preset threshold
/// dropdowns, the same idiom Finviz itself uses, rather than free-text
/// fields) applied client-side to whatever rows a ScreenerClient already
/// fetched. The backend's lists are already short top-20/25 screens, so
/// there's no need for a backend filter API - this only narrows what's
/// already in memory, shared across all three screener tabs.
library;

import 'screener_models.dart';

class ScreenerFilters {
  final double minChangePercent;
  final double minVolume;
  final double minMarketCap;

  const ScreenerFilters({
    this.minChangePercent = 0,
    this.minVolume = 0,
    this.minMarketCap = 0,
  });

  bool get isActive => minChangePercent > 0 || minVolume > 0 || minMarketCap > 0;

  List<ScreenerRow> apply(List<ScreenerRow> rows) {
    if (!isActive) return rows;
    return rows
        .where((r) =>
            r.changePercent.abs() >= minChangePercent &&
            r.volume >= minVolume &&
            r.marketCap >= minMarketCap)
        .toList();
  }

  ScreenerFilters copyWith({
    double? minChangePercent,
    double? minVolume,
    double? minMarketCap,
  }) {
    return ScreenerFilters(
      minChangePercent: minChangePercent ?? this.minChangePercent,
      minVolume: minVolume ?? this.minVolume,
      minMarketCap: minMarketCap ?? this.minMarketCap,
    );
  }
}
