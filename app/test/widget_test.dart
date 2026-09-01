import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/main.dart';

void main() {
  testWidgets('starts with one empty purchase panel', (tester) async {
    await tester.pumpWidget(const StockCalcApp());
    expect(find.text('Purchase 1'), findsOneWidget);
    // "New Purchase" is now a compact icon button, not a labeled card.
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('Ctrl+N adds a second panel', (tester) async {
    await tester.pumpWidget(const StockCalcApp());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Purchase 1'), findsOneWidget);
    expect(find.text('Purchase 2'), findsOneWidget);
  });
}
