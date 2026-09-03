/// The shared screener row shape served over /screener/top. Filtering and
/// sorting both happen on Finviz's side now (see finviz_client.dart) - this
/// is purely the wire format, not a place to re-filter what Finviz already
/// decided belongs on the "unusual volume" screen.
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

  const ScreenerRow({
    required this.symbol,
    required this.name,
    this.exchange = '',
    this.sector = '',
    required this.marketCap,
    required this.price,
    required this.changePercent,
    required this.volume,
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
      };
}
