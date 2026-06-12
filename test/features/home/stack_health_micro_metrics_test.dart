import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/home/v2/home_v2_screen.dart';

/// Regression test for the Stack Health micro-metrics truncation bug:
/// "0 supplements" / "0 medications" ellipsized to "0 supplem…" /
/// "0 medicati…" at iPhone widths (393pt logical). The fix stacks the
/// count over a short noun label, mirroring Stack v2's count chips.
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

  /// Asserts the label can never ellipsize: the pre-fix code rendered
  /// "0 supplements" with `maxLines: 1` + `TextOverflow.ellipsis`, which
  /// produced "0 supplem…" at 393pt. The fixed labels carry neither, so
  /// the full string always paints (wrapping in the worst case — the
  /// test environment's Ahem font is far wider than production fonts).
  void expectNotTruncated(WidgetTester tester, String text) {
    final widget = tester.widget<Text>(find.text(text));
    expect(
      widget.overflow,
      isNot(TextOverflow.ellipsis),
      reason: '"$text" must not be ellipsizable',
    );
    expect(
      widget.maxLines,
      isNull,
      reason: '"$text" must not be clamped to a line count',
    );
  }

  testWidgets('labels fit without truncation at 393pt card width', (
    tester,
  ) async {
    await pumpMetrics(tester);

    expect(tester.takeException(), isNull);
    for (final label in ['Supplements', 'Medications', 'No conflicts']) {
      expect(find.text(label), findsOneWidget);
      expectNotTruncated(tester, label);
    }
  });

  testWidgets('renders counts stacked over labels', (tester) async {
    await pumpMetrics(tester, supplements: 3, medications: 1);

    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Supplements'), findsOneWidget);
    expect(find.text('Medications'), findsOneWidget);
  });

  testWidgets('survives an even tighter width without overflow errors', (
    tester,
  ) async {
    // 320pt screen (smallest supported) minus the same paddings.
    await pumpMetrics(tester, width: 320.0 - 96.0);

    expect(tester.takeException(), isNull);
    expectNotTruncated(tester, 'Supplements');
    expectNotTruncated(tester, 'Medications');
  });
}
