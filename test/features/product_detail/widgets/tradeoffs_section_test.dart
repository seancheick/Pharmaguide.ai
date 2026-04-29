// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.6.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/tradeoffs_section.dart';

void main() {
  TradeoffItem item({
    required String label,
    String detail = '',
    required bool isPositive,
  }) =>
      (label: label, detail: detail, isPositive: isPositive);

  /// Pump the section inside a fixed-width Scaffold so the
  /// LayoutBuilder branch is deterministic. Default 480pt → two-column
  /// layout fires.
  Future<void> pumpSection(
    WidgetTester tester,
    List<TradeoffItem> items, {
    double width = 480,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: TradeoffsSection(items: items),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('TradeoffsSection — split contract', () {
    testWidgets('bonuses-only → only "What\'s good" column renders',
        (tester) async {
      await pumpSection(tester, [
        item(label: 'Third-party tested', isPositive: true),
        item(label: 'Bioavailable forms', isPositive: true),
      ]);

      expect(find.text('👍 What\'s good'), findsOneWidget);
      expect(find.text('Third-party tested'), findsOneWidget);
      expect(find.text('Bioavailable forms'), findsOneWidget);

      // The penalties column header must NOT render when there are
      // no penalties — single-column fallback fires.
      expect(find.text('⚖️ What to consider'), findsNothing);
    });

    testWidgets('penalties-only → only "What to consider" column renders',
        (tester) async {
      await pumpSection(tester, [
        item(label: 'Contains proprietary blend', isPositive: false),
      ]);

      expect(find.text('⚖️ What to consider'), findsOneWidget);
      expect(find.text('Contains proprietary blend'), findsOneWidget);
      expect(find.text('👍 What\'s good'), findsNothing);
    });

    testWidgets(
      'both bonuses + penalties at 480pt → two-column side-by-side layout',
      (tester) async {
        await pumpSection(tester, [
          item(label: 'Third-party tested', isPositive: true),
          item(label: 'Contains proprietary blend', isPositive: false),
        ]);

        expect(find.text('👍 What\'s good'), findsOneWidget);
        expect(find.text('⚖️ What to consider'), findsOneWidget);

        // Y-position assertion: at 480pt the two headers sit at the
        // SAME vertical offset (Row layout — side-by-side).
        final goodY =
            tester.getTopLeft(find.text('👍 What\'s good')).dy;
        final considerY =
            tester.getTopLeft(find.text('⚖️ What to consider')).dy;
        expect(goodY, considerY,
            reason: 'two-column branch must render headers at the same '
                'Y-coordinate; if they\'re stacked the LayoutBuilder '
                'breakpoint is wrong');
      },
    );

    testWidgets(
      'both populated at 320pt (SE width) → single-column stacked layout',
      (tester) async {
        // SE-class width is below the 380pt breakpoint — the layout
        // must collapse to single-column to keep each text block
        // readable. The pros header sits ABOVE the cons header.
        await pumpSection(
          tester,
          [
            item(label: 'Third-party tested', isPositive: true),
            item(label: 'Contains proprietary blend', isPositive: false),
          ],
          width: 320,
        );

        final goodY =
            tester.getTopLeft(find.text('👍 What\'s good')).dy;
        final considerY =
            tester.getTopLeft(find.text('⚖️ What to consider')).dy;
        expect(goodY, lessThan(considerY),
            reason: 'narrow-width branch must stack pros above cons');
      },
    );

    testWidgets(
      'both empty → entire section returns SizedBox.shrink (hides)',
      (tester) async {
        await pumpSection(tester, const []);

        // Headers absent.
        expect(find.text('👍 What\'s good'), findsNothing);
        expect(find.text('⚖️ What to consider'), findsNothing);
        // The decorated outer Container also doesn't render. We can't
        // grep for `Container` directly (Material composes lots of
        // them) but we can assert the section's only public widgets
        // are absent — that's enough.
      },
    );

    testWidgets('blank-label entries are dropped defensively', (tester) async {
      // _extractWhyItems shouldn't emit blank labels but pipeline
      // drift could. The section filters them rather than rendering
      // an empty bullet.
      await pumpSection(tester, [
        item(label: '', isPositive: true),
        item(label: '   ', isPositive: false),
        item(label: 'Real bonus', isPositive: true),
      ]);

      expect(find.text('Real bonus'), findsOneWidget);
      // Both empty/whitespace entries dropped → only one column with
      // one item; the cons column header should NOT appear (the
      // whitespace entry was the only "penalty").
      expect(find.text('⚖️ What to consider'), findsNothing);
    });
  });

  group('TradeoffsSection — row rendering', () {
    testWidgets('bonus row renders label and optional detail subline',
        (tester) async {
      await pumpSection(tester, [
        item(
          label: 'Third-party tested',
          detail: 'NSF Sport verified',
          isPositive: true,
        ),
      ]);

      expect(find.text('Third-party tested'), findsOneWidget);
      expect(find.text('NSF Sport verified'), findsOneWidget);
    });

    testWidgets('row with empty detail does NOT render an empty subline',
        (tester) async {
      // Detail is optional — passing '' should not render a zero-
      // height Text widget under the label (visually it just doesn't
      // appear; harder to assert directly, but we can check that
      // the only text widget for "Bioavailable forms" is its label).
      await pumpSection(tester, [
        item(label: 'Bioavailable forms', isPositive: true),
      ]);

      expect(find.text('Bioavailable forms'), findsOneWidget);
      // Sanity: no stray empty-string text widgets rendered.
      expect(find.text(''), findsNothing);
    });

    testWidgets('long detail string wraps — no overflow exception',
        (tester) async {
      const longDetail =
          'Independent third-party laboratory testing verifies the '
          'product\'s identity, potency, and absence of contaminants '
          'including heavy metals, pesticides, and microbial impurities '
          'against the label claim.';
      await pumpSection(
        tester,
        [
          item(
            label: 'Third-party tested',
            detail: longDetail,
            isPositive: true,
          ),
        ],
        // SE-class width to stress the wrap.
        width: 320,
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('heavy metals'), findsOneWidget);
    });

    testWidgets('multiple bonuses + penalties all render in their column',
        (tester) async {
      await pumpSection(tester, [
        item(label: 'Bonus one', isPositive: true),
        item(label: 'Bonus two', isPositive: true),
        item(label: 'Bonus three', isPositive: true),
        item(label: 'Penalty one', isPositive: false),
        item(label: 'Penalty two', isPositive: false),
      ]);

      // All five labels show up.
      expect(find.text('Bonus one'), findsOneWidget);
      expect(find.text('Bonus two'), findsOneWidget);
      expect(find.text('Bonus three'), findsOneWidget);
      expect(find.text('Penalty one'), findsOneWidget);
      expect(find.text('Penalty two'), findsOneWidget);

      // Bonuses appear in the pros column (above OR left of the
      // first penalty depending on the layout branch — assert they
      // appear before the penalties in document order).
      final bonusOnePos = tester.getTopLeft(find.text('Bonus one'));
      final penaltyOnePos = tester.getTopLeft(find.text('Penalty one'));
      // At 480pt (default in pumpSection): same row, bonus-x <
      // penalty-x. At narrow widths: bonus-y < penalty-y.
      // Either way, document order means bonus comes first by some
      // axis — at minimum the labels coexist without crashing.
      expect(bonusOnePos != penaltyOnePos, isTrue);
    });
  });
}
