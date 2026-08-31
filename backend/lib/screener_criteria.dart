/// Pure filter/sort logic for the screener, kept separate from any network
/// code so it's trivially unit-testable. Mirrors the Finviz "unusual volume"
/// view the user wants replicated: micro-cap, sorted by % change descending.
library;

class ScreenerRow {
  final String symbol;
  final String name;
  final String exchange;
  final double marketCap;
  final double price;
  final double changePercent;
  final double volume;

  const ScreenerRow({
    required this.symbol,
    required this.name,
    required this.exchange,
    required this.marketCap,
    required this.price,
    required this.changePercent,
    required this.volume,
  });

  factory ScreenerRow.fromJson(Map<String, dynamic> json) => ScreenerRow(
        symbol: json['symbol'] as String,
        name: json['name'] as String,
        exchange: json['exchange'] as String,
        marketCap: (json['marketCap'] as num).toDouble(),
        price: (json['price'] as num).toDouble(),
        changePercent: (json['changePercent'] as num).toDouble(),
        volume: (json['volume'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'name': name,
        'exchange': exchange,
        'marketCap': marketCap,
        'price': price,
        'changePercent': changePercent,
        'volume': volume,
      };
}

class ScreenerCriteria {
  final double maxMarketCap;
  final double minChangePercent;
  final double? maxChangePercent;

  const ScreenerCriteria({
    this.maxMarketCap = 500e6,
    this.minChangePercent = 10.0,
    this.maxChangePercent,
  });

  bool matches(ScreenerRow row) {
    if (row.marketCap <= 0 || row.marketCap > maxMarketCap) return false;
    final change = row.changePercent.abs();
    if (change < minChangePercent) return false;
    if (maxChangePercent != null && change > maxChangePercent!) return false;
    return true;
  }
}

List<ScreenerRow> applyScreener(List<ScreenerRow> rows, ScreenerCriteria criteria, {int limit = 5}) {
  final filtered = rows.where(criteria.matches).toList()
    ..sort((a, b) => b.changePercent.abs().compareTo(a.changePercent.abs()));
  return filtered.take(limit).toList();
}
