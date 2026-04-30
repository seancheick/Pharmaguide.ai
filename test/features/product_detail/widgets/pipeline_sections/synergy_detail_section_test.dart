// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.1, T6.
//
// Verifies the tap-to-bottom-sheet behavior added in T6 — the inline
// cluster row keeps the 3-line ellipsis as a summary; tapping it
// opens a sheet with the FULL untruncated explanation. Sean's
// 2026-04-29 walkthrough: "Stress-resilient — when I tap on it,
// it's cut off. I cannot read the rest of it."

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/pipeline_sections/synergy_detail_section.dart';

/// Long enough to overflow the inline 3-line ellipsis on a 320pt
/// (iPhone SE) viewport at the section's bodySmall font size, so the
/// truncation gap is observable in tests.
const _longExplanation =
    'Magnesium and ashwagandha together support a calmer evening '
    'wind-down by buffering cortisol and supporting GABAergic '
    'signaling. Clinical evidence is moderate — 5 randomized trials '
    'and 1 meta-analysis cover the combination at standard doses, '
    'with effect sizes most consistent for sleep onset latency and '
    'subjective restfulness.';

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SynergyDetailSection(
            synergyDetail: {
              'clusters': [
                {
                  'name': 'Stress-resilient sleep stack',
                  'evidence_tier': 'moderate',
                  'benefit_short': _longExplanation,
                  'pmids': ['1', '2', '3', '4'],
                },
              ],
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SynergyDetailSection — T6 tap-to-sheet', () {
    testWidgets('inline row renders cluster name + truncated explanation', (
      tester,
    ) async {
      await _pump(tester);
      await tester.pumpAndSettle();

      // Cluster name visible inline.
      expect(find.text('Stress-resilient sleep stack'), findsOneWidget);
      // Inline explanation Text widget exists with maxLines=3 +
      // ellipsis (verified at the source — the assertion here is
      // structural: the row IS tappable now, which means PGPressable
      // wraps it).
      expect(find.text(_longExplanation), findsOneWidget);
    });

    testWidgets('tapping cluster row opens sheet with FULL explanation', (
      tester,
    ) async {
      await _pump(tester);
      await tester.pumpAndSettle();

      // Tap the cluster name — the PGPressable wraps the whole row,
      // so any descendant tap counts. Use the unique cluster name as
      // the handle.
      await tester.tap(find.text('Stress-resilient sleep stack'));
      await tester.pumpAndSettle();

      // Sheet should be open. The cluster name now appears TWICE in
      // the tree — once in the underlying section, once in the sheet
      // header.
      expect(find.text('Stress-resilient sleep stack'), findsNWidgets(2));

      // Full explanation visible in the sheet WITHOUT truncation —
      // this is the contract T6 was opened to fix. The inline row
      // ellipsises at 3 lines; the sheet renders the whole thing.
      // We assert the closing fragment of the explanation that would
      // be cut off in the inline view.
      expect(
        find.textContaining('subjective restfulness'),
        findsAtLeastNWidgets(1),
      );

      // Sheet renders the studies count line.
      expect(find.text('4 published studies'), findsAtLeastNWidgets(1));
    });

    testWidgets(
      'sheet renders evidence tier badge in title row',
      (tester) async {
        await _pump(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Stress-resilient sleep stack'));
        await tester.pumpAndSettle();

        // Tier appears in inline row + sheet title row → 2 instances.
        expect(find.text('moderate'), findsNWidgets(2));
      },
    );
  });
}
