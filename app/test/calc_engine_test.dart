// Ported 1:1 from tests/testCalcEngine.cpp (12 scenarios / ~34 assertions)
// for parity with the old C++ calc engine test suite.
import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/core/calc_engine.dart';

void main() {
  test('basicProfit', () {
    final r = calculatePanel(const PanelInput(
      totalInvestment: 1000.0,
      sharePrice: 50.0,
      totalShares: 20.0,
      targetPrice: 75.0,
    ));
    expect(r.profit, closeTo(500.0, 0.01));
    expect(r.profitPlusInvest, closeTo(1500.0, 0.01));
    expect(r.gainPercent, closeTo(50.0, 0.01));
  });

  test('inferShares', () {
    final r = calculatePanel(const PanelInput(
      totalInvestment: 1000.0,
      sharePrice: 25.0,
      lastChanged: 2,
      secondLastChanged: 1,
    ));
    expect(r.totalShares, closeTo(40.0, 0.01));
    expect(r.inferredField, 3);
  });

  test('inferPrice', () {
    final r = calculatePanel(const PanelInput(
      totalInvestment: 500.0,
      totalShares: 10.0,
      lastChanged: 3,
      secondLastChanged: 1,
    ));
    expect(r.sharePrice, closeTo(50.0, 0.01));
    expect(r.inferredField, 2);
  });

  test('inferInvestment', () {
    final r = calculatePanel(const PanelInput(
      sharePrice: 100.0,
      totalShares: 5.0,
      lastChanged: 3,
    ));
    expect(r.totalInvestment, closeTo(500.0, 0.01));
    expect(r.inferredField, 1);
  });

  test('zeroTarget', () {
    final r = calculatePanel(const PanelInput(
      totalInvestment: 1000.0,
      sharePrice: 50.0,
      totalShares: 20.0,
    ));
    expect(r.profit, closeTo(0.0, 0.01));
    expect(r.profitPlusInvest, closeTo(0.0, 0.01));
  });

  test('negativeProfit', () {
    final r = calculatePanel(const PanelInput(
      totalInvestment: 1000.0,
      sharePrice: 50.0,
      totalShares: 20.0,
      targetPrice: 30.0,
    ));
    expect(r.profit, closeTo(-400.0, 0.01));
    expect(r.gainPercent, closeTo(-40.0, 0.01));
  });

  test('combinedStats', () {
    final panels = [
      const PanelResult(
          totalInvestment: 1000.0, sharePrice: 50.0, totalShares: 20.0, profit: 500.0),
      const PanelResult(
          totalInvestment: 2000.0, sharePrice: 100.0, totalShares: 20.0, profit: -200.0),
    ];
    final c = calculateCombined(panels);
    expect(c.validCount, 2);
    expect(c.totalInvestment, closeTo(3000.0, 0.01));
    expect(c.totalShares, closeTo(40.0, 0.01));
    expect(c.totalProfit, closeTo(300.0, 0.01));
    expect(c.avgProfit, closeTo(150.0, 0.01));
    expect(c.avgSharePrice, closeTo(75.0, 0.01));
  });

  test('combinedEmpty', () {
    final c = calculateCombined(const []);
    expect(c.validCount, 0);
    expect(c.totalInvestment, closeTo(0.0, 0.01));
  });

  test('combinedSkipsInvalid', () {
    final panels = [
      const PanelResult(
          totalInvestment: 500.0, sharePrice: 25.0, totalShares: 20.0, profit: 100.0),
      const PanelResult(),
    ];
    final c = calculateCombined(panels);
    expect(c.validCount, 1);
    expect(c.totalInvestment, closeTo(500.0, 0.01));
  });

  test('inferFallbackTwoNonzero', () {
    final r = calculatePanel(const PanelInput(
      totalInvestment: 0.0,
      sharePrice: 40.0,
      totalShares: 10.0,
    ));
    expect(r.totalInvestment, closeTo(400.0, 0.01));
    expect(r.inferredField, 1);
  });

  test('largeNumbers', () {
    final r = calculatePanel(const PanelInput(
      totalInvestment: 1000000.0,
      sharePrice: 500.0,
      totalShares: 2000.0,
      targetPrice: 750.0,
    ));
    expect(r.profit, closeTo(500000.0, 0.01));
    expect(r.gainPercent, closeTo(50.0, 0.01));
  });

  test('fieldTracking', () {
    expect(isValidTrackingField(FieldId.totalInvestment), true);
    expect(isValidTrackingField(FieldId.sharePrice), true);
    expect(isValidTrackingField(FieldId.totalShares), true);
    expect(isValidTrackingField(FieldId.targetPrice), false);
    expect(isValidTrackingField(FieldId.none), false);
    expect(isValidTrackingField(FieldId.profit), false);
    expect(isValidTrackingField(FieldId.profitInvest), false);
  });
}
