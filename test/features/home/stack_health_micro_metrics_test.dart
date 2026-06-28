import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/home/v2/home_v2_screen.dart';

/// Regression test for the Stack Health micro-metrics truncation bug:
/// "0 supplements" / "0 medications" ellipsized to "0 supplem…" /
/// "0 medicati…" at iPhone widths (393pt logical), then regressed into
/// a two-line "Supplement" + "s" wrap. The fixed row keeps each metric
/// on one line.
void main() {
  // Card content width at a 393pt screen: 393 − 24·2 (screen padding)
  // − 24·2 (card padding) = 297pt. Tightest realistic harness.
  const cardContentWidth = 297.0;

  Future<void> pumpMetrics(
    WidgetTester tester, {
    double width = cardContentWidth,
    int supplements = 0,
    int medications = 0,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: StackHealthMicroMetrics(
                supplementCount: supplements,
                medicationCount: medications,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void expectOneLineMetricText(WidgetTester tester, String text) {
    final widget = tester.widget<Text>(find.text(text));
    expect(
      widget.overflow,
      isNot(TextOverflow.ellipsis),
      reason: '"$text" must not be ellipsizable',
    );
    expect(widget.maxLines, 1, reason: '"$text" must be locked to one line');
    expect(
      widget.softWrap,
      isFalse,
      reason: '"$text" must not wrap the plural suffix to a second line',
    );
  }

  testWidgets('metrics fit as one-line labels at 393pt card width', (
    tester,
  ) async {
    await pumpMetrics(tester, supplements: 2);

    expect(tester.takeException(), isNull);
    for (final label in ['2 Supplements', '0 Medications', 'No conflicts']) {
      expect(find.text(label), findsOneWidget);
      expectOneLineMetricText(tester, label);
    }
  });

  testWidgets('renders counts inline with labels', (tester) async {
    await pumpMetrics(tester, supplements: 3, medications: 1);

    expect(find.text('3 Supplements'), findsOneWidget);
    expect(find.text('1 Medication'), findsOneWidget);
    expect(find.text('No conflicts'), findsOneWidget);
  });

  testWidgets('metric labels share the same visual row', (tester) async {
    await pumpMetrics(tester, supplements: 2);

    final supplementCenter = tester.getCenter(find.text('2 Supplements')).dy;
    final medicationCenter = tester.getCenter(find.text('0 Medications')).dy;
    final conflictCenter = tester.getCenter(find.text('No conflicts')).dy;

    expect((supplementCenter - medicationCenter).abs(), lessThan(1));
    expect((supplementCenter - conflictCenter).abs(), lessThan(1));
  });

  testWidgets('survives an even tighter width without overflow errors', (
    tester,
  ) async {
    // 320pt screen (smallest supported) minus the same paddings.
    await pumpMetrics(tester, width: 320.0 - 96.0);

    expect(tester.takeException(), isNull);
    expectOneLineMetricText(tester, '0 Supplements');
    expectOneLineMetricText(tester, '0 Medications');
  });
}
