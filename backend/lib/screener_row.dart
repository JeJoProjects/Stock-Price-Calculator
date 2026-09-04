/// The shared screener row shape served over /screener/finviz, /screener/yahoo
/// and /screener/combined. Filtering and sorting happen on each source's side
/// (see finviz_client.dart / yahoo_client.dart) - this is purely the wire
/// format, not a place to re-filter what a source already decided belongs on
/// its movers screen.
library;

class ScreenerRow {
  final String symbol;
  final String name;
  final String exchange;
  final String sector;
  final double marketCap;
  final double price;
  final double changePercent;
  final double volume;
  // Which source(s) this row came from: 'finviz', 'yahoo', or 'both' for the
  // /screener/combined intersection. Defaults to '' so existing call sites
  // that don't set it (if any) still compile.
  final String source;

  const ScreenerRow({
    required this.symbol,
    required this.name,
    this.exchange = '',
    this.sector = '',
    required this.marketCap,
    required this.price,
    required this.changePercent,
    required this.volume,
    this.source = '',
  });

  factory ScreenerRow.fromJson(Map<String, dynamic> json) => ScreenerRow(
        symbol: json['symbol'] as String,
        name: json['name'] as String,
        exchange: json['exchange'] as String? ?? '',
        sector: json['sector'] as String? ?? '',
        marketCap: (json['marketCap'] as num).toDouble(),
        price: (json['price'] as num).toDouble(),
        changePercent: (json['changePercent'] as num).toDouble(),
        volume: (json['volume'] as num).toDouble(),
        source: json['source'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'symbol': symbol,
        'name': name,
        'exchange': exchange,
        'sector': sector,
        'marketCap': marketCap,
        'price': price,
        'changePercent': changePercent,
        'volume': volume,
        'source': source,
      };
}
