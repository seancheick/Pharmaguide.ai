// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T15.
//
// Verifies the Tradeoffs cleanup:
//   - "Harmful additive X" rows collapse into a single combined
//     "Additive: X, Y, Z" row
//   - Per-side cap at 4 bullets, with "… and N more concerns"
//     muted footer for the overflow
//   - The literal "Harmful additive" prefix never reaches the
//     rendered widget tree

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/tradeoffs_section.dart';

TradeoffItem _bonus(String label, [String detail = '']) => (
  label: label,
  detail: detail,
  isPositive: true,
);

TradeoffItem _penalty(String label, [String detail = '']) => (
  label: label,
  detail: detail,
  isPositive: false,
);

Future<void> _pump(WidgetTester tester, List<TradeoffItem> items) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: TradeoffsSection(items: items),
        ),
      ),
    ),
  );
}

void main() {
  group('collapseHarmfulAdditives — pure helper (T15)', () {
    test('empty list → empty list', () {
      expect(collapseHarmfulAdditives(const []), isEmpty);
    });

    test('non-additive penalties pass through unchanged', () {
      final input = [
        _penalty('Proprietary blend'),
        _penalty('Below RDA for daily magnesium'),
      ];
      expect(collapseHarmfulAdditives(input), input);
    });

    test('single "Harmful additive X" → single "Additive: X" row', () {
      final result = collapseHarmfulAdditives([
        _penalty('Harmful additive Sugar syrup'),
      ]);
      expect(result, hasLength(1));
      expect(result.first.label, 'Additive: Sugar syrup');
    });

    test('multiple harmful additives → ONE combined row', () {
      final result = collapseHarmfulAdditives([
        _penalty('Harmful additive Sugar syrup'),
        _penalty('Harmful additive Palm oil'),
        _penalty('Harmful additive Red 40'),
      ]);
      expect(result, hasLength(1));
      expect(result.first.label, 'Additive: Sugar syrup, Palm oil, Red 40');
      expect(result.first.isPositive, isFalse);
    });

    test('mixed: harmful additives collapse + non-additive penalties retained', () {
      final result = collapseHarmfulAdditives([
        _penalty('Proprietary blend'),
        _penalty('Harmful additive Sugar syrup'),
        _penalty('Harmful additive Palm oil'),
        _penalty('Below RDA for daily magnesium'),
      ]);
      expect(result, hasLength(3));
      // Combined "Additives:" row goes to the FRONT.
      expect(result.first.label, 'Additive: Sugar syrup, Palm oil');
      expect(result[1].label, 'Proprietary blend');
      expect(result[2].label, 'Below RDA for daily magnesium');
    });

    test('case-insensitive match against pipeline drift', () {
      // Pipeline could ship "harmful additive" / "HARMFUL ADDITIVE".
      // Helper matches against lowercase prefix so all variants
      // collapse.
      final result = collapseHarmfulAdditives([
        _penalty('Harmful additive Sugar syrup'),
        _penalty('harmful additive Palm oil'),
        _penalty('HARMFUL ADDITIVE Red 40'),
      ]);
      expect(result, hasLength(1));
      expect(result.first.label, 'Additive: Sugar syrup, Palm oil, Red 40');
    });

    test(
      '2026-04-30 — colon-form prefix "Harmful additive: NAME" also collapses',
      () {
        // Live pipeline ships the colon form (Sean's PureLean
        // walkthrough). Pre-fix, only the no-colon form matched and
        // colon-form labels rendered as raw repeats.
        final result = collapseHarmfulAdditives([
          _penalty('Harmful additive: Modified Food Starch'),
          _penalty('Harmful additive: Silicon Dioxide (E551)'),
        ]);
        expect(result, hasLength(1));
        expect(
          result.first.label,
          'Additive: Modified Food Starch, Silicon Dioxide (E551)',
        );
      },
    );

    test(
      '2026-04-30 — dedupes same name (case-insensitive) across multiple emits',
      () {
        // Pipeline sometimes emits the same additive twice (e.g. from
        // two source fields). The combined bullet should list each
        // unique name only once.
        final result = collapseHarmfulAdditives([
          _penalty('Harmful additive: Modified Food Starch'),
          _penalty('Harmful additive: Modified Food Starch'),
          _penalty('Harmful additive: modified food starch'),
          _penalty('Harmful additive: Silicon Dioxide'),
        ]);
        expect(result, hasLength(1));
        expect(
          result.first.label,
          'Additive: Modified Food Starch, Silicon Dioxide',
        );
      },
    );

    test(
      '2026-04-30 — never says "Harmful" in output (Sean: too harsh)',
      () {
        final result = collapseHarmfulAdditives([
          _penalty('Harmful additive Sugar'),
          _penalty('harmful additive: Palm oil'),
        ]);
        expect(result.first.label, isNot(contains('Harmful')));
        expect(result.first.label, isNot(contains('harmful')));
        expect(result.first.label.startsWith('Additive: '), isTrue);
      },
    );
  });

  group('TradeoffsSection — T15 collapse + cap render', () {
    testWidgets('"Harmful additive" prefix never reaches rendered tree', (
      tester,
    ) async {
      await _pump(tester, [
        _penalty('Harmful additive Sugar syrup'),
        _penalty('Harmful additive Palm oil'),
      ]);
      await tester.pumpAndSettle();

      // Combined row IS rendered.
      expect(find.text('Additive: Sugar syrup, Palm oil'), findsOneWidget);
      // Original prefixed labels are NOT.
      expect(find.text('Harmful additive Sugar syrup'), findsNothing);
      expect(find.text('Harmful additive Palm oil'), findsNothing);
    });

    testWidgets('4 penalties render fully, no toggle', (tester) async {
      await _pump(tester, [
        _penalty('Concern A'),
        _penalty('Concern B'),
        _penalty('Concern C'),
        _penalty('Concern D'),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Concern A'), findsOneWidget);
      expect(find.text('Concern D'), findsOneWidget);
      expect(find.textContaining('Show'), findsNothing);
    });

    testWidgets(
      'T15.1 — 6 penalties → 4 visible + "Show 2 more concerns" toggle',
      (tester) async {
        await _pump(tester, [
          _penalty('Concern A'),
          _penalty('Concern B'),
          _penalty('Concern C'),
          _penalty('Concern D'),
          _penalty('Concern E'),
          _penalty('Concern F'),
        ]);
        await tester.pumpAndSettle();

        // First 4 visible.
        expect(find.text('Concern A'), findsOneWidget);
        expect(find.text('Concern D'), findsOneWidget);
        // Items 5 and 6 hidden behind toggle.
        expect(find.text('Concern E'), findsNothing);
        expect(find.text('Concern F'), findsNothing);
        // Tappable toggle text.
        expect(find.text('Show 2 more concerns'), findsOneWidget);
      },
    );

    testWidgets(
      'T15.1 — tap toggle expands the list in place',
      (tester) async {
        await _pump(tester, [
          _penalty('Concern A'),
          _penalty('Concern B'),
          _penalty('Concern C'),
          _penalty('Concern D'),
          _penalty('Concern E'),
          _penalty('Concern F'),
        ]);
        await tester.pumpAndSettle();

        // Tap the toggle.
        await tester.tap(find.text('Show 2 more concerns'));
        await tester.pumpAndSettle();

        // All 6 visible now.
        expect(find.text('Concern A'), findsOneWidget);
        expect(find.text('Concern E'), findsOneWidget);
        expect(find.text('Concern F'), findsOneWidget);
        // Toggle copy flips to "Show less".
        expect(find.text('Show less'), findsOneWidget);
        expect(find.text('Show 2 more concerns'), findsNothing);
      },
    );

    testWidgets(
      'T15.1 — tap "Show less" collapses back',
      (tester) async {
        await _pump(tester, [
          _penalty('Concern A'),
          _penalty('Concern B'),
          _penalty('Concern C'),
          _penalty('Concern D'),
          _penalty('Concern E'),
        ]);
        await tester.pumpAndSettle();

        // Expand.
        await tester.tap(find.text('Show 1 more concern'));
        await tester.pumpAndSettle();
        expect(find.text('Concern E'), findsOneWidget);
        // Collapse.
        await tester.tap(find.text('Show less'));
        await tester.pumpAndSettle();
        expect(find.text('Concern E'), findsNothing);
        expect(find.text('Show 1 more concern'), findsOneWidget);
      },
    );

    testWidgets(
      'T15.1 — 5 bonuses → "Show 1 more bonus" (singular)',
      (tester) async {
        await _pump(tester, [
          _bonus('Bonus A'),
          _bonus('Bonus B'),
          _bonus('Bonus C'),
          _bonus('Bonus D'),
          _bonus('Bonus E'),
        ]);
        await tester.pumpAndSettle();

        expect(find.text('Bonus A'), findsOneWidget);
        expect(find.text('Bonus D'), findsOneWidget);
        expect(find.text('Bonus E'), findsNothing);
        expect(find.text('Show 1 more bonus'), findsOneWidget);
      },
    );

    testWidgets(
      'T15.1 — 6 bonuses → "Show 2 more bonuses" (correct plural, not "bonuss")',
      (tester) async {
        await _pump(tester, [
          _bonus('A'),
          _bonus('B'),
          _bonus('C'),
          _bonus('D'),
          _bonus('E'),
          _bonus('F'),
        ]);
        await tester.pumpAndSettle();
        // Pluralizer must add 'es' for "bonus" (ending in 's') so it
        // reads "bonuses" not "bonuss".
        expect(find.text('Show 2 more bonuses'), findsOneWidget);
        expect(find.text('Show 2 more bonuss'), findsNothing);
      },
    );

    testWidgets(
      'collapse + cap interplay — 5 additives + 3 other concerns → 4 visible, no toggle',
      (tester) async {
        // 5 harmful additives collapse to 1 combined row + 3 other
        // concerns = 4 penalties total → no overflow.
        await _pump(tester, [
          _penalty('Harmful additive Sugar'),
          _penalty('Harmful additive Palm'),
          _penalty('Harmful additive Red 40'),
          _penalty('Harmful additive Yellow 5'),
          _penalty('Harmful additive Aspartame'),
          _penalty('Proprietary blend'),
          _penalty('Below RDA'),
          _penalty('Old reformulation'),
        ]);
        await tester.pumpAndSettle();

        // Combined additives row rendered.
        expect(
          find.text('Additive: Sugar, Palm, Red 40, Yellow 5, Aspartame'),
          findsOneWidget,
        );
        // After collapse there are 4 penalties; cap = 4 → no toggle.
        expect(find.text('Proprietary blend'), findsOneWidget);
        expect(find.text('Below RDA'), findsOneWidget);
        expect(find.text('Old reformulation'), findsOneWidget);
        expect(find.textContaining('Show'), findsNothing);
      },
    );

    testWidgets('empty input → section hides entirely', (tester) async {
      await _pump(tester, const []);
      await tester.pumpAndSettle();
      expect(find.text('👍 What\'s good'), findsNothing);
      expect(find.text('⚖️ What to consider'), findsNothing);
    });
  });
}
