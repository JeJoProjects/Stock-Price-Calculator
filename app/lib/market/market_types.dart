/// Client-side mirror of backend/lib/market_types.dart, decoded from the
/// backend's /quote, /profile, /candles JSON responses.
library;

enum Timeframe { day1, week1, month1, month6, year1, max }

extension TimeframeInfo on Timeframe {
  String get label => switch (this) {
        Timeframe.day1 => '1D',
        Timeframe.week1 => '1W',
        Timeframe.month1 => '1M',
        Timeframe.month6 => '6M',
        Timeframe.year1 => '1Y',
        Timeframe.max => 'MAX',
      };
}

class Candle {
  final int time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory Candle.fromJson(Map<String, dynamic> json) => Candle(
        time: (json['time'] as num).toInt(),
        open: (json['open'] as num).toDouble(),
        high: (json['high'] as num).toDouble(),
        low: (json['low'] as num).toDouble(),
        close: (json['close'] as num).toDouble(),
        volume: (json['volume'] as num).toDouble(),
      );

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(time * 1000);
}

class Quote {
  final double current;
  final double change;
  final double percent;
  final double high;
  final double low;
  final double open;
  final double previousClose;

  const Quote({
    this.current = 0.0,
    this.change = 0.0,
    this.percent = 0.0,
    this.high = 0.0,
    this.low = 0.0,
    this.open = 0.0,
    this.previousClose = 0.0,
  });

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        current: (json['current'] as num).toDouble(),
        change: (json['change'] as num).toDouble(),
        percent: (json['percent'] as num).toDouble(),
        high: (json['high'] as num).toDouble(),
        low: (json['low'] as num).toDouble(),
        open: (json['open'] as num).toDouble(),
        previousClose: (json['previousClose'] as num).toDouble(),
      );
}

class CompanyProfile {
  final String name;
  final String exchange;
  final String currency;
  final double marketCap;

  const CompanyProfile({
    this.name = '',
    this.exchange = '',
    this.currency = '',
    this.marketCap = 0.0,
  });

  factory CompanyProfile.fromJson(Map<String, dynamic> json) => CompanyProfile(
        name: json['name'] as String? ?? '',
        exchange: json['exchange'] as String? ?? '',
        currency: json['currency'] as String? ?? '',
        marketCap: (json['marketCap'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Ported from market::Snapshot (marketTypes.hpp): bundles everything the
/// chart pane needs for one symbol+timeframe, with loading/error state so
/// the UI can show "Updating..." or an error message like the old app did.
class MarketSnapshot {
  final String symbol;
  final Timeframe timeframe;
  final Quote? quote;
  final CompanyProfile? profile;
  final List<Candle> candles;
  final bool loading;
  final String? error;

  const MarketSnapshot({
    required this.symbol,
    required this.timeframe,
    this.quote,
    this.profile,
    this.candles = const [],
    this.loading = false,
    this.error,
  });

  bool get isValid => quote != null && candles.isNotEmpty;
}
