// Regression test for Bug 9 (Sean 2026-05-17 walkthrough):
//
// On TestFlight 1.0.0+3 + 1.0.0+4, tapping an "Other ingredient" row
// on Product Detail v2 did nothing — the v2 ingredients section
// hardcoded `onInactiveTap: null` because the v1 `_FunctionalRolesSheet`
// was private. This test locks in the fix shipped in 1.0.0+5:
// `showFunctionalRolesSheet` was extracted to its own file, and the
// v2 section wires the tap to it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/data/functional_roles_vocab.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/ingredients_section.dart';

void main() {
  setUp(() {
    debugSetFunctionalRolesVocabForTesting({
      'lubricant': const FunctionalRole(
        id: 'lubricant',
        name: 'Lubricant',
        notes: 'Keeps powder from sticking during pressing.',
        regulatoryReferences: [],
        examples: ['magnesium stearate'],
      ),
    });
  });

  tearDown(() {
    debugSetFunctionalRolesVocabForTesting(null);
  });

  testWidgets(
    'v2 inactive tile tap opens functional-roles sheet (Bug 9 regression)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => SingleChildScrollView(
                child: buildIngredientsSection(
                  context: ctx,
                  ingredients: const [],
                  inactiveIngredients: const [
                    {
                      'name': 'Magnesium Stearate',
                      'functional_roles': ['lubricant'],
                    },
                  ],
                  ulAnalysis: const [],
                  blends: const [],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1 inactive is below `PGIngredientsCard.autoExpandThreshold`
      // (5) so the row is already visible without toggling the
      // header.
      expect(find.text('Magnesium Stearate'), findsWidgets);

      // Pre-fix: this tap was a no-op (`onInactiveTap: null`).
      // Post-fix: it opens the sheet via showFunctionalRolesSheet.
      await tester.tap(find.text('Magnesium Stearate'));
      await tester.pumpAndSettle();

      // Sheet body asserts: header echoes the ingredient name + the
      // vocab role name + notes appear.
      expect(find.text('Lubricant'), findsOneWidget);
      expect(
        find.text('Keeps powder from sticking during pressing.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'v2 inactive tile with empty functional_roles still opens sheet (generic fallback)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => SingleChildScrollView(
                child: buildIngredientsSection(
                  context: ctx,
                  ingredients: const [],
                  inactiveIngredients: const [
                    {
                      'name': 'Mystery Excipient',
                      'functional_roles': <String>[],
                    },
                  ],
                  ulAnalysis: const [],
                  blends: const [],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mystery Excipient'));
      await tester.pumpAndSettle();

      // Generic fallback copy proves the sheet opened even with empty
      // roles — the tap is no longer a no-op.
      expect(
        find.text('Inactive ingredient — added during manufacturing.'),
        findsOneWidget,
      );
    },
  );
}
