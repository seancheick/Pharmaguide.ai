import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/features/settings/v2/beta_feedback_sheet.dart';

void main() {
  Future<void> pumpSheet(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // Scrollable host: the sheet is taller than the default test
            // viewport, and we are not exercising layout here.
            body: SingleChildScrollView(
              child: BetaFeedbackSheet(openExternal: (_) async => true),
            ),
          ),
        ),
      );

  PGPillButton button(WidgetTester tester, String label) =>
      tester.widget<PGPillButton>(find.widgetWithText(PGPillButton, label));

  testWidgets('Send is gated on choosing a category AND an impact', (
    tester,
  ) async {
    await pumpSheet(tester);

    // Disabled with nothing selected.
    expect(button(tester, 'Send feedback').onPressed, isNull);

    await tester.tap(find.text('Bug'));
    await tester.pump();
    expect(
      button(tester, 'Send feedback').onPressed,
      isNull,
      reason: 'category alone is not enough',
    );

    await tester.tap(find.text('Frustrating'));
    await tester.pump();
    expect(
      button(tester, 'Send feedback').onPressed,
      isNotNull,
      reason: 'both selected → enabled',
    );
  });

  testWidgets('Add detail by email is always available', (tester) async {
    await pumpSheet(tester);
    expect(button(tester, 'Add detail by email').onPressed, isNotNull);
  });
}
