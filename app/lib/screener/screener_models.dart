/// Client-side mirror of backend/lib/screener_criteria.dart's ScreenerRow,
/// decoded from the /screener/top JSON response.
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
}

class ScreenerSnapshot {
  final List<ScreenerRow> rows;
  final DateTime? lastUpdated;
  final String? error;

  const ScreenerSnapshot({this.rows = const [], this.lastUpdated, this.error});

  factory ScreenerSnapshot.fromJson(Map<String, dynamic> json) => ScreenerSnapshot(
        rows: (json['rows'] as List).map((r) => ScreenerRow.fromJson(r)).toList(),
        lastUpdated:
            json['lastUpdated'] != null ? DateTime.tryParse(json['lastUpdated'] as String) : null,
        error: json['error'] as String?,
      );
}
