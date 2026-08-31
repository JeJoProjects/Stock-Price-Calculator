import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/core/formatting.dart';

void main() {
  test('formatNumber with 0 decimals has no trailing dot', () {
    expect(formatNumber(8000, decimals: 0), '8,000');
  });

  test('formatNumber with 2 decimals keeps them', () {
    expect(formatNumber(8000, decimals: 2), '8,000.00');
  });

  test('formatCurrency', () {
    expect(formatCurrency(1234.5), '\$1,234.50');
    expect(formatCurrency(-1234.5), '-\$1,234.50');
  });

  test('formatProfit em-dash near zero', () {
    expect(formatProfit(0.001), '—');
    expect(formatProfit(500), '+\$500.00');
    expect(formatProfit(-500), '-\$500.00');
  });

  test('formatGain em-dash near zero', () {
    expect(formatGain(0.001), '—');
    expect(formatGain(20), '+20.00%');
  });
}
