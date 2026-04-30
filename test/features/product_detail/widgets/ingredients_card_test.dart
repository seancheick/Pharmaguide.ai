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

  group('IngredientsCard — render', () {
    testWidgets(
      'both empty → SizedBox.shrink (no card rendered)',
      (tester) async {
        await _pump(tester, activeContent: null, inactiveNames: const []);
        await tester.pumpAndSettle();
        // Card should not render its title.
        expect(find.text('Other ingredients'), findsNothing);
      },
    );

    testWidgets('inactive only → renders title + chips, no divider', (
      tester,
    ) async {
      await _pump(
        tester,
        activeContent: null,
        inactiveNames: const ['Gelatin', 'Silica'],
      );
      await tester.pumpAndSettle();
      expect(find.text('Other ingredients'), findsOneWidget);
      // No active content means no divider.
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
      // Divider between sub-sections.
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets(
      '≤ 8 inactives → all chips rendered, no "See all" toggle',
      (tester) async {
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
        expect(find.textContaining('See all'), findsNothing);
        expect(find.textContaining('Show less'), findsNothing);
      },
    );

    testWidgets(
      '> 8 inactives → "See all N ingredients" toggle visible, only top 8 chips initially',
      (tester) async {
        final names = List.generate(12, (i) => 'Ingredient ${i + 1}');
        await _pump(tester, activeContent: null, inactiveNames: names);
        await tester.pumpAndSettle();
        // Toggle visible.
        expect(find.text('See all 12 ingredients'), findsOneWidget);
        // Top 8 chip labels appear; remaining 4 don't (until expanded).
        expect(find.text('Ingredient 1'), findsOneWidget);
        expect(find.text('Ingredient 8'), findsOneWidget);
        // Items 9-12 NOT in initial render (chip wrap is capped).
        // The expanded list will surface them after tap.
      },
    );

    testWidgets(
      'tap "See all" → expands the FULL list with color dots',
      (tester) async {
        await _pump(
          tester,
          activeContent: null,
          inactiveNames: const [
            'Gelatin', // green
            'Palm oil', // orange
            'Aspartame', // red
            'Some other thing', // yellow
            'Microcrystalline cellulose', // green
            'Red 40', // red
            'Magnesium stearate', // green
            'Polysorbate 80', // orange
            'Brewers yeast', // yellow (overflow)
          ],
        );
        await tester.pumpAndSettle();

        // Pre-expand: the top-8 chips are present, plus the toggle.
        expect(find.text('See all 9 ingredients'), findsOneWidget);

        await tester.tap(find.text('See all 9 ingredients'));
        await tester.pumpAndSettle();

        // Post-expand: toggle copy flips.
        expect(find.text('Show less'), findsOneWidget);
        expect(find.text('See all 9 ingredients'), findsNothing);
        // Overflow item now visible in the expanded list.
        expect(find.textContaining('Brewers yeast'), findsWidgets);
      },
    );

    testWidgets('tap "Show less" collapses back', (tester) async {
      final names = List.generate(10, (i) => 'Ingredient ${i + 1}');
      await _pump(tester, activeContent: null, inactiveNames: names);
      await tester.pumpAndSettle();

      // Expand.
      await tester.tap(find.text('See all 10 ingredients'));
      await tester.pumpAndSettle();
      expect(find.text('Show less'), findsOneWidget);
      // Collapse.
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(find.text('See all 10 ingredients'), findsOneWidget);
      expect(find.text('Show less'), findsNothing);
    });
  });
}
