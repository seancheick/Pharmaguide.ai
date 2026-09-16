import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_tradeoffs_section.dart';

// 2026-09-16 walkthrough: side-by-side columns on a phone squeezed long
// "What to consider" copy into a narrow strip. Phones stack the columns;
// wide layouts keep them side by side.
Future<void> _pumpAtWidth(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PGTradeoffsSection(
            pros: [PGTradeoff(headline: 'Audited GMP facility')],
            considerations: [
              PGTradeoff(
                headline:
                    'Total potency is disclosed; individual strain amounts '
                    'are not.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone width stacks What to consider under What\'s good', (
    tester,
  ) async {
    await _pumpAtWidth(tester, 402);

    final good = tester.getTopLeft(find.text('WHAT\'S GOOD'));
    final consider = tester.getTopLeft(find.text('WHAT TO CONSIDER'));
    expect(consider.dx, good.dx);
    expect(consider.dy, greaterThan(good.dy));
  });

  testWidgets('wide layouts keep the two columns side by side', (tester) async {
    await _pumpAtWidth(tester, 900);

    final good = tester.getTopLeft(find.text('WHAT\'S GOOD'));
    final consider = tester.getTopLeft(find.text('WHAT TO CONSIDER'));
    expect(consider.dy, good.dy);
    expect(consider.dx, greaterThan(good.dx));
  });
}
