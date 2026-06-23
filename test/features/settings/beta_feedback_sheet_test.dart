import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/features/settings/v2/beta_feedback_sheet.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    SubmitBetaFeedback? submitFeedback,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // Scrollable host: the sheet is taller than the default test
        // viewport, and we are not exercising layout here.
        body: SingleChildScrollView(
          child: BetaFeedbackSheet(
            openExternal: (_) async => true,
            submitFeedback: submitFeedback,
          ),
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

  testWidgets('disabled Sentry keeps sheet open and points to email fallback', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      submitFeedback: ({required category, required impact}) async =>
          PgFeedbackSubmissionResult.disabled,
    );

    await tester.tap(find.text('Bug'));
    await tester.tap(find.text('Minor'));
    await tester.pump();
    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();

    expect(find.text('Send beta feedback'), findsOneWidget);
    expect(find.text('Send feedback'), findsOneWidget);
    expect(
      find.text(
        'Feedback is not enabled in this build. Add detail by email instead.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('capture failure keeps sheet open and points to email fallback', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      submitFeedback: ({required category, required impact}) async =>
          PgFeedbackSubmissionResult.failed,
    );

    await tester.tap(find.text('Bug'));
    await tester.tap(find.text('Minor'));
    await tester.pump();
    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();

    expect(find.text('Send beta feedback'), findsOneWidget);
    expect(find.text('Send feedback'), findsOneWidget);
    expect(
      find.text('Could not send feedback. Add detail by email instead.'),
      findsOneWidget,
    );
  });
}
