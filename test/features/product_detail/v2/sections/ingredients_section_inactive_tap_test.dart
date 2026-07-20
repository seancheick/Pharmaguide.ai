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

  testWidgets('nutrient total renders label forms as nested components', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => SingleChildScrollView(
              child: buildIngredientsSection(
                context: ctx,
                ingredients: const [],
                displayIngredients: const [
                  {
                    'label_display_name': 'Vitamin A',
                    'exact_dose_text': '1.05 mg',
                    'nested_depth': 0,
                    'score_included': true,
                  },
                  {
                    'label_display_name': 'Beta-Carotene',
                    'exact_dose_text': '450 mcg',
                    'nested_depth': 1,
                    'parent_label': 'Vitamin A',
                    'score_included': true,
                  },
                  {
                    'label_display_name': 'Vitamin A Palmitate',
                    'label_display_form': 'retinyl palmitate',
                    'exact_dose_text': '600 mcg',
                    'nested_depth': 1,
                    'parent_label': 'Vitamin A',
                    'form_display_state': 'assessed',
                    'score_included': true,
                  },
                ],
                inactiveIngredients: const [],
                ulAnalysis: const [],
                blends: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vitamin A'), findsOneWidget);
    expect(find.text('Components of Vitamin A'), findsOneWidget);
    expect(find.text('Beta-Carotene'), findsOneWidget);
    expect(find.text('Vitamin A Palmitate'), findsOneWidget);
    expect(find.text('retinyl palmitate'), findsOneWidget);
    expect(find.text('450 mcg'), findsOneWidget);
    expect(find.text('600 mcg'), findsOneWidget);
  });

  testWidgets('canonical blend ledger renders header and every label child', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => SingleChildScrollView(
              child: buildIngredientsSection(
                context: ctx,
                ingredients: const [],
                displayIngredients: const [
                  {
                    'label_display_name': 'Botanical Blend',
                    'display_type': 'structural_container',
                    'quantity': 100,
                    'unit': 'mg',
                    'nested_depth': 0,
                    'children': ['Ashwagandha', 'Rhodiola'],
                    'score_included': true,
                  },
                  {
                    'label_display_name': 'Ashwagandha',
                    'exact_dose_text': 'Amount not disclosed',
                    'nested_depth': 1,
                    'parent_label': 'Botanical Blend',
                    'form_display_state': 'not_applicable',
                    'score_included': false,
                  },
                  {
                    'label_display_name': 'Rhodiola',
                    'exact_dose_text': 'Amount not disclosed',
                    'nested_depth': 1,
                    'parent_label': 'Botanical Blend',
                    'form_display_state': 'not_applicable',
                    'score_included': false,
                  },
                ],
                inactiveIngredients: const [],
                ulAnalysis: const [],
                blends: const [
                  {
                    'name': 'Botanical Blend',
                    'total_weight': 100,
                    'unit': 'mg',
                    'child_ingredients': [
                      {'name': 'Ashwagandha', 'amount': null, 'unit': ''},
                      {'name': 'Rhodiola', 'amount': null, 'unit': ''},
                    ],
                  },
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Proprietary blend'), findsOneWidget);
    expect(find.text('Botanical Blend'), findsOneWidget);
    expect(find.text('Components of Botanical Blend'), findsOneWidget);
    expect(find.text('100 mg'), findsOneWidget);
    expect(find.text('Ashwagandha'), findsOneWidget);
    expect(find.text('Rhodiola'), findsOneWidget);
    expect(find.text('Amount not disclosed'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('ingredient-view-analysis')));
    await tester.pumpAndSettle();

    expect(find.text('Proprietary blend'), findsNothing);
    expect(find.text('Botanical Blend'), findsOneWidget);
    await tester.tap(find.text('Botanical Blend'));
    await tester.pumpAndSettle();
    expect(
      find.text('Educational use only — not medical advice.'),
      findsOneWidget,
    );
  });

  testWidgets('canonical probiotic blend explains alternative serving totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => SingleChildScrollView(
              child: buildIngredientsSection(
                context: ctx,
                ingredients: const [],
                displayIngredients: const [
                  {
                    'label_display_name': 'Probiotic Blend',
                    'display_type': 'structural_container',
                    'exact_dose_text': '2.25 billion CFU',
                    'nested_depth': 0,
                    'children': ['Bifidobacterium bifidum (Bb-06)'],
                    'score_included': true,
                    'serving_variants': [
                      {
                        'serving_note': 'Ages 1-3 (1/2 scoop)',
                        'exact_dose_text': '1.12 billion CFU',
                        'is_canonical': false,
                      },
                      {
                        'serving_note': 'Ages 4 and up (1 scoop)',
                        'exact_dose_text': '2.25 billion CFU',
                        'is_canonical': true,
                      },
                    ],
                  },
                  {
                    'label_display_name': 'Bifidobacterium bifidum (Bb-06)',
                    'nested_depth': 1,
                    'parent_label': 'Probiotic Blend',
                    'score_included': false,
                  },
                ],
                inactiveIngredients: const [],
                ulAnalysis: const [],
                blends: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2.25 billion CFU'), findsNWidgets(2));
    expect(find.text('Serving amounts on label'), findsOneWidget);
    expect(find.text('Ages 1-3 (1/2 scoop)'), findsOneWidget);
    expect(find.text('1.12 billion CFU'), findsOneWidget);
    expect(find.text('Ages 4 and up (1 scoop)'), findsOneWidget);
    expect(find.text('Selected serving'), findsOneWidget);
    expect(find.text('Bifidobacterium bifidum (Bb-06)'), findsOneWidget);
  });
}
