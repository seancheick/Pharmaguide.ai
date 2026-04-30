// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T16.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredients_card.dart';

Future<void> _pump(
  WidgetTester tester, {
  Widget? activeContent,
  required List<String> inactiveNames,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: IngredientsCard(
              activeContent: activeContent,
              inactiveNames: inactiveNames,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('inactiveColorRank — pure helper (T16)', () {
    test('whitelisted excipient → green', () {
      // Defers to standard_excipients.dart's whitelist for these.
      expect(inactiveColorRank('gelatin'), InactiveTone.green);
      expect(inactiveColorRank('vegetable cellulose'), InactiveTone.green);
      expect(inactiveColorRank('magnesium stearate'), InactiveTone.green);
    });

    test('artificial dye → red', () {
      expect(inactiveColorRank('Red 40'), InactiveTone.red);
      expect(inactiveColorRank('yellow 5'), InactiveTone.red);
      expect(inactiveColorRank('Blue 1'), InactiveTone.red);
    });

    test('artificial sweetener → red', () {
      expect(inactiveColorRank('Aspartame'), InactiveTone.red);
      expect(inactiveColorRank('sucralose'), InactiveTone.red);
    });

    test('common syrups → red', () {
      expect(inactiveColorRank('Sugar syrup'), InactiveTone.red);
      expect(inactiveColorRank('high fructose corn syrup'), InactiveTone.red);
    });

    test('partially hydrogenated oils → red', () {
      expect(
        inactiveColorRank('Partially hydrogenated soybean oil'),
        InactiveTone.red,
      );
    });

    test('palm oil and watchlist → orange', () {
      expect(inactiveColorRank('Palm oil'), InactiveTone.orange);
      expect(inactiveColorRank('Carrageenan'), InactiveTone.orange);
      expect(inactiveColorRank('titanium dioxide'), InactiveTone.orange);
    });

    test('unknown ingredient (not in any set) → yellow', () {
      expect(inactiveColorRank('Some unusual ingredient'), InactiveTone.yellow);
      expect(inactiveColorRank('Brewers yeast'), InactiveTone.yellow);
    });

    test('empty string → yellow (defensive)', () {
      expect(inactiveColorRank(''), InactiveTone.yellow);
      expect(inactiveColorRank('   '), InactiveTone.yellow);
    });

    test('case-insensitive match', () {
      expect(inactiveColorRank('PALM OIL'), InactiveTone.orange);
      expect(inactiveColorRank('aspartame'), InactiveTone.red);
      expect(inactiveColorRank('GELATIN'), InactiveTone.green);
    });
  });

  group('IngredientsCard — render (post-2026-04-30 collapsible)', () {
    testWidgets(
      'both empty → SizedBox.shrink (no card rendered)',
      (tester) async {
        await _pump(tester, activeContent: null, inactiveNames: const []);
        await tester.pumpAndSettle();
        expect(find.text('Other ingredients'), findsNothing);
      },
    );

    testWidgets('inactive only → renders title + count badge, no divider', (
      tester,
    ) async {
      await _pump(
        tester,
        activeContent: null,
        inactiveNames: const ['Gelatin', 'Silica'],
      );
      await tester.pumpAndSettle();
      expect(find.text('Other ingredients'), findsOneWidget);
      // Count badge shows the number.
      expect(find.text('2'), findsOneWidget);
      // No active content → no inter-sub-section divider.
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('active + inactive → divider rendered between', (tester) async {
      await _pump(
        tester,
        activeContent: const Text('ACTIVE_BLOCK'),
        inactiveNames: const ['Gelatin'],
      );
      await tester.pumpAndSettle();
      expect(find.text('ACTIVE_BLOCK'), findsOneWidget);
      expect(find.text('Other ingredients'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets(
      '≤ 5 inactives → auto-expands so all rows visible by default',
      (tester) async {
        // Mirrors `_CollapsibleIngredientsState`'s autoExpand-if-≤5
        // contract on the actives side.
        await _pump(
          tester,
          activeContent: null,
          inactiveNames: const [
            'Gelatin',
            'Silica',
            'Cellulose',
            'Magnesium stearate',
          ],
        );
        await tester.pumpAndSettle();
        // Each name renders inline (not behind a "See all" toggle).
        expect(find.text('Gelatin'), findsOneWidget);
        expect(find.text('Silica'), findsOneWidget);
        expect(find.text('Cellulose'), findsOneWidget);
        expect(find.text('Magnesium stearate'), findsOneWidget);
        // Chevron is still present (header is tappable to collapse).
        expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
      },
    );

    testWidgets(
      '> 5 inactives → starts collapsed; tap header expands the full list',
      (tester) async {
        final names = List.generate(12, (i) => 'Ingredient ${i + 1}');
        await _pump(tester, activeContent: null, inactiveNames: names);
        await tester.pumpAndSettle();

        // Count badge shows total.
        expect(find.text('12'), findsOneWidget);
        // Pre-expand: rows hidden (long list defaults collapsed).
        expect(find.text('Ingredient 1'), findsNothing);

        // Tap header to expand.
        await tester.tap(find.text('Other ingredients'));
        await tester.pumpAndSettle();

        // All rows now visible inline.
        expect(find.text('Ingredient 1'), findsOneWidget);
        expect(find.text('Ingredient 12'), findsOneWidget);
      },
    );

    testWidgets(
      'tap header twice toggles collapse → expand → collapse',
      (tester) async {
        final names = List.generate(10, (i) => 'Ingredient ${i + 1}');
        await _pump(tester, activeContent: null, inactiveNames: names);
        await tester.pumpAndSettle();

        // Starts collapsed (length > 5).
        expect(find.text('Ingredient 1'), findsNothing);

        // Expand.
        await tester.tap(find.text('Other ingredients'));
        await tester.pumpAndSettle();
        expect(find.text('Ingredient 1'), findsOneWidget);

        // Collapse.
        await tester.tap(find.text('Other ingredients'));
        await tester.pumpAndSettle();
        expect(find.text('Ingredient 1'), findsNothing);
      },
    );
  });
}
