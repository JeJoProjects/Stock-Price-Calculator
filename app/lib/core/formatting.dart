/// Number/currency formatting, ported from src/ui/imguiHelpers.hpp so the
/// displayed values match the old app exactly ($1,234.56, +/- prefixes, em-dash
/// for ~zero, etc).
library;

import 'package:intl/intl.dart';

final _grouped2dp = NumberFormat('#,##0.00', 'en_US');

String formatCurrency(double v) {
  final sign = v < 0 ? '-' : '';
  return '$sign\$${_grouped2dp.format(v.abs())}';
}

String formatProfit(double v) {
  if (v.abs() < 0.005) return '—';
  final sign = v < 0 ? '-' : '+';
  return '$sign\$${_grouped2dp.format(v.abs())}';
}

String formatGain(double v) {
  if (v.abs() < 0.005) return '—';
  final sign = v < 0 ? '-' : '+';
  return '$sign${_grouped2dp.format(v.abs())}%';
}

String formatPercent(double v) => '${_grouped2dp.format(v)}%';

String formatNumber(double v, {int decimals = 2}) {
  final pattern = decimals > 0 ? '#,##0.${'0' * decimals}' : '#,##0';
  return NumberFormat(pattern, 'en_US').format(v);
}

/// Used when writing an inferred value back into a text field: empty for
/// exactly zero, otherwise a plain (non-grouped) 2-decimal number.
String formatValue(double v) {
  if (v == 0.0) return '';
  return v.toStringAsFixed(2);
}

String formatCompactMarketCap(double v) {
  if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(2)}B';
  if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(2)}M';
  return formatCurrency(v);
}

/// Share volume, compact (e.g. 1.2M, 845.0K). Zero (or missing, when
/// Finnhub's candle endpoint isn't available on the current plan) renders
/// as an em-dash rather than "0", per the app's zero-value convention.
String formatCompactVolume(double v) {
  if (v <= 0) return '—';
  if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
  if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
  return v.toStringAsFixed(0);
}
