import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockcalc/main.dart';

void main() {
  // The default test surface (800x600) is narrower than this desktop app's
  // default window (1600x900, see AppSettings) and no longer leaves enough
  // room for a purchase panel once both the Micro-Cap Movers rail (320px)
  // and the chart sidebar (340px) are reserved - match the real default
  // window size so layout assertions reflect actual usage.
  void useDesktopSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('starts with one empty purchase panel', (tester) async {
    useDesktopSurface(tester);
    await tester.pumpWidget(const StockCalcApp());
    expect(find.text('Purchase 1'), findsOneWidget);
    // "New Purchase" is now a compact icon button, not a labeled card.
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('Ctrl+N adds a second panel', (tester) async {
    useDesktopSurface(tester);
    await tester.pumpWidget(const StockCalcApp());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Purchase 1'), findsOneWidget);
    expect(find.text('Purchase 2'), findsOneWidget);
  });
}
