/// Ported from src/market/marketTypes.hpp/.cpp.
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

  String get resolution => switch (this) {
        Timeframe.day1 => '5',
        Timeframe.week1 => '15',
        Timeframe.month1 => '60',
        Timeframe.month6 => 'D',
        Timeframe.year1 => 'D',
        Timeframe.max => 'W',
      };

  int get lookbackDays => switch (this) {
        Timeframe.day1 => 10,
        Timeframe.week1 => 30,
        Timeframe.month1 => 90,
        Timeframe.month6 => 180,
        Timeframe.year1 => 365,
        Timeframe.max => 3650,
      };

  static Timeframe fromLabel(String label) => Timeframe.values.firstWhere(
        (t) => t.label == label.toUpperCase(),
        orElse: () => Timeframe.day1,
      );
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

  Map<String, dynamic> toJson() =>
      {'time': time, 'open': open, 'high': high, 'low': low, 'close': close, 'volume': volume};
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

  bool get isValid => current > 0.0;

  Map<String, dynamic> toJson() => {
        'current': current,
        'change': change,
        'percent': percent,
        'high': high,
        'low': low,
        'open': open,
        'previousClose': previousClose,
      };
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

  bool get isValid => name.isNotEmpty;

  Map<String, dynamic> toJson() =>
      {'name': name, 'exchange': exchange, 'currency': currency, 'marketCap': marketCap};
}
