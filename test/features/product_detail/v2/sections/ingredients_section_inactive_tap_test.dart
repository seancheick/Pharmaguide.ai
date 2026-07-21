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
import 'package:pharmaguide/core/components/pg_ingredient_tile.dart';
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

    // Blend header and every label child render directly in the single label
    // view — there is no Analysis toggle to switch between.
    expect(find.text('Botanical Blend'), findsOneWidget);
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

  testWidgets(
    'canonical ledger has clear nutrition active and other sections',
    (tester) async {
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
                      'label_display_name': 'Calories',
                      'display_type': 'nutrition_fact',
                      'exact_dose_text': '20 Calories',
                      'nested_depth': 0,
                      'score_included': false,
                    },
                    {
                      'label_display_name': 'Daily Blend',
                      'display_type': 'structural_container',
                      'nested_depth': 0,
                      'children': ['Zinc', 'Copper'],
                      'score_included': false,
                    },
                    {
                      'label_display_name': 'Zinc',
                      'display_type': 'mapped_ingredient',
                      'nested_depth': 1,
                      'parent_label': 'Daily Blend',
                      'score_included': true,
                    },
                    {
                      'label_display_name': 'Copper',
                      'display_type': 'mapped_ingredient',
                      'nested_depth': 1,
                      'parent_label': 'Daily Blend',
                      'score_included': true,
                    },
                    {
                      'label_display_name': 'Rice Flour',
                      'display_type': 'inactive_ingredient',
                      'display_disposition': 'other_ingredient',
                      'nested_depth': 0,
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

      expect(find.text('Nutrition facts'), findsOneWidget);
      expect(find.text('Active ingredients'), findsOneWidget);
      expect(find.text('Other ingredients'), findsOneWidget);
      expect(find.text('What the label lists'), findsNothing);
      // Four actual label rows render as tiles. The structural blend parent is
      // a header, not a fifth ingredient tile.
      expect(find.byType(PGActiveIngredientTile), findsNWidgets(4));
      expect(find.text('Calories'), findsOneWidget);
      expect(find.text('Rice Flour'), findsOneWidget);
    },
  );

  testWidgets(
    'omega totals and unscored children stay with their active parent',
    (tester) async {
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
                      'label_display_name': 'Fish Oil',
                      'display_type': 'mapped_ingredient',
                      'raw_source_path': 'ingredientRows[0]',
                      'nested_depth': 0,
                      'score_included': true,
                    },
                    {
                      'label_display_name': 'Total Omega-3 Fatty Acids',
                      'display_type': 'nutrition_fact',
                      'raw_source_path': 'ingredientRows[0].nestedRows[0]',
                      'parent_source_path': 'ingredientRows[0]',
                      'parent_label': 'Fish Oil',
                      'nested_depth': 1,
                      'score_included': false,
                    },
                    {
                      'label_display_name': 'EPA',
                      'display_type': 'mapped_ingredient',
                      'raw_source_path':
                          'ingredientRows[0].nestedRows[0].nestedRows[0]',
                      'parent_source_path': 'ingredientRows[0].nestedRows[0]',
                      'parent_label': 'Total Omega-3 Fatty Acids',
                      'nested_depth': 2,
                      'score_included': true,
                    },
                    {
                      'label_display_name': 'DHA',
                      'display_type': 'mapped_ingredient',
                      'raw_source_path':
                          'ingredientRows[0].nestedRows[0].nestedRows[1]',
                      'parent_source_path': 'ingredientRows[0].nestedRows[0]',
                      'parent_label': 'Total Omega-3 Fatty Acids',
                      'nested_depth': 2,
                      'score_included': true,
                    },
                    {
                      'label_display_name': 'Other Omega-3',
                      'display_type': 'nutrition_fact',
                      'raw_source_path':
                          'ingredientRows[0].nestedRows[0].nestedRows[2]',
                      'parent_source_path': 'ingredientRows[0].nestedRows[0]',
                      'parent_label': 'Total Omega-3 Fatty Acids',
                      'nested_depth': 2,
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

      expect(find.text('Nutrition facts'), findsNothing);
      final activeTop = tester.getTopLeft(find.text('Active ingredients')).dy;
      expect(
        tester.getTopLeft(find.text('Total Omega-3 Fatty Acids')).dy,
        greaterThan(activeTop),
      );
      expect(
        tester.getTopLeft(find.text('Other Omega-3')).dy,
        greaterThan(activeTop),
      );
    },
  );

  testWidgets('hierarchy guide does not double-indent nested label rows', (
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
                    'label_display_name': 'Fish Oil',
                    'display_type': 'mapped_ingredient',
                    'raw_source_path': 'ingredientRows[0]',
                    'nested_depth': 0,
                    'score_included': true,
                  },
                  {
                    'label_display_name': 'EPA',
                    'display_type': 'mapped_ingredient',
                    'raw_source_path':
                        'ingredientRows[0].nestedRows[0].nestedRows[0]',
                    'parent_source_path': 'ingredientRows[0]',
                    'parent_label': 'Fish Oil',
                    'nested_depth': 2,
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

    final parentX = tester.getTopLeft(find.text('Fish Oil')).dx;
    final childX = tester.getTopLeft(find.text('EPA')).dx;
    expect(childX - parentX, lessThanOrEqualTo(12));
  });
}
