// Regression test for Bug 9 (Sean 2026-05-17 walkthrough):
//
// On TestFlight 1.0.0+3 + 1.0.0+4, tapping an "Other ingredient" row
// on Product Detail v2 did nothing — the v2 ingredients section
// hardcoded `onInactiveTap: null` because the v1 `_FunctionalRolesSheet`
// was private. This test locks in the fix shipped in 1.0.0+5:
// `showFunctionalRolesSheet` was extracted to its own file, and the
// v2 section wires the tap to it.

import 'package:flutter/foundation.dart';
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

  group('ingredient disclosure target availability', () {
    test('canonical ledger is authoritative when present but empty', () {
      expect(
        hasIngredientDisclosureTarget(
          ingredients: const [
            {'name': 'Legacy active'},
          ],
          displayIngredients: const [],
          blends: const [],
        ),
        isFalse,
      );
    });

    test('canonical nutrition and other-only ledgers have no target', () {
      expect(
        hasIngredientDisclosureTarget(
          ingredients: const [],
          displayIngredients: const [
            {
              'display_type': 'nutrition_fact',
              'label_display_name': 'Calories',
            },
            {
              'display_type': 'inactive_ingredient',
              'label_display_name': 'Rice flour',
            },
            {
              'display_disposition': 'other_ingredient',
              'label_display_name': 'Silica',
            },
          ],
          blends: const [],
        ),
        isFalse,
      );
    });

    test('canonical nested rows use their root ledger section', () {
      expect(
        hasIngredientDisclosureTarget(
          ingredients: const [
            {'name': 'Legacy active'},
          ],
          displayIngredients: const [
            {
              'display_type': 'nutrition_fact',
              'label_display_name': 'Total Fat',
              'raw_source_path': 'ingredientRows[0]',
            },
            {
              'display_type': 'mapped_ingredient',
              'label_display_name': 'Omega-3',
              'raw_source_path': 'ingredientRows[0].nestedRows[0]',
              'parent_source_path': 'ingredientRows[0]',
            },
          ],
          blends: const [],
        ),
        isFalse,
      );
    });

    test('canonical active ledger row has a target', () {
      expect(
        hasIngredientDisclosureTarget(
          ingredients: const [],
          displayIngredients: const [
            {
              'display_type': 'mapped_ingredient',
              'label_display_name': 'Vitamin D',
            },
          ],
          blends: const [],
        ),
        isTrue,
      );
    });

    test('legacy inactive-only data has no target', () {
      expect(
        hasIngredientDisclosureTarget(
          ingredients: const [],
          displayIngredients: null,
          blends: const [],
        ),
        isFalse,
      );
    });

    test('unmatched legacy blend metadata has no target', () {
      expect(
        hasIngredientDisclosureTarget(
          ingredients: const [],
          displayIngredients: null,
          blends: const [
            {
              'name': 'Raw Blend',
              'child_ingredients': [
                {'name': 'Metadata-only child', 'amount': null},
              ],
            },
          ],
        ),
        isFalse,
      );
    });

    test('deduped legacy active row has a target', () {
      expect(
        hasIngredientDisclosureTarget(
          ingredients: const [
            {'name': 'Magnesium', 'canonical_id': 'magnesium', 'quantity': 60},
            {
              'name': 'Magnesium Glycinate',
              'canonical_id': 'magnesium',
              'quantity': 400,
            },
          ],
          displayIngredients: null,
          blends: const [],
        ),
        isTrue,
      );
    });
  });

  testWidgets(
    'canonical target prefers a named blend label with normalized whitespace',
    (tester) async {
      final targetKey = GlobalKey();
      await _pumpIngredients(
        tester,
        displayIngredients: const [
          {'label_display_name': 'Vitamin C'},
          {'label_display_name': '  Daily   Botanical Blend  '},
          {'label_display_name': 'Zinc'},
        ],
        blends: const [
          {'name': 'daily botanical blend'},
        ],
        disclosureTargetKey: targetKey,
      );

      expect(find.byKey(targetKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(targetKey),
          matching: find.text('Daily   Botanical Blend'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(targetKey),
          matching: find.text('Vitamin C'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'canonical target ignores a harmless trademark mark on a named blend',
    (tester) async {
      final targetKey = GlobalKey();
      await _pumpIngredients(
        tester,
        displayIngredients: const [
          {'label_display_name': 'Vitamin C'},
          {'label_display_name': 'Daily Botanical Blend™'},
          {'label_display_name': 'Zinc'},
        ],
        blends: const [
          {'name': 'Daily Botanical Blend'},
        ],
        disclosureTargetKey: targetKey,
      );

      expect(find.byKey(targetKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(targetKey),
          matching: find.text('Daily Botanical Blend™'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(targetKey),
          matching: find.text('Vitamin C'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('canonical target falls back to the first active row', (
    tester,
  ) async {
    final targetKey = GlobalKey();
    await _pumpIngredients(
      tester,
      displayIngredients: const [
        {'label_display_name': 'First active'},
        {'label_display_name': 'Second active'},
      ],
      blends: const [],
      disclosureTargetKey: targetKey,
    );

    expect(find.byKey(targetKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(targetKey),
        matching: find.text('First active'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(targetKey),
        matching: find.text('Second active'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'pre-requested reveal mounts the target when the section first builds',
    (tester) async {
      final targetKey = GlobalKey();
      final revealSignal = ValueNotifier<bool>(true);
      addTearDown(revealSignal.dispose);

      await _pumpIngredients(
        tester,
        displayIngredients: [
          for (var index = 0; index < 6; index++)
            {'label_display_name': 'Ordinary active $index'},
          {
            'display_type': 'structural_container',
            'label_display_name': 'Pre-requested blend target',
            'children': const ['Blend child'],
          },
        ],
        blends: const [],
        disclosureTargetKey: targetKey,
        disclosureRevealSignal: revealSignal,
      );

      expect(targetKey.currentContext, isNotNull);
      expect(find.byKey(targetKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(targetKey),
          matching: find.text('Pre-requested blend target'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'canonical reveal mounts the preferred structural row from a collapsed section',
    (tester) async {
      final targetKey = GlobalKey();
      final revealSignal = _RevealSignal();
      addTearDown(revealSignal.dispose);
      await _pumpIngredients(
        tester,
        displayIngredients: [
          for (var index = 0; index < 6; index++)
            {'label_display_name': 'Ordinary active $index'},
          {
            'display_type': 'structural_container',
            'label_display_name': 'Preferred structural blend',
            'children': const ['Blend child'],
          },
        ],
        blends: const [],
        disclosureTargetKey: targetKey,
        disclosureRevealSignal: revealSignal,
      );

      expect(find.text('Active ingredients'), findsOneWidget);
      expect(targetKey.currentContext, isNull);
      expect(find.byKey(targetKey), findsNothing);

      revealSignal.reveal();
      await tester.pumpAndSettle();

      expect(targetKey.currentContext, isNotNull);
      expect(find.byKey(targetKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(targetKey),
          matching: find.text('Preferred structural blend'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('legacy target prefers the first actual grouped blend header', (
    tester,
  ) async {
    final targetKey = GlobalKey();
    await _pumpIngredients(
      tester,
      ingredients: const [
        {'name': 'Loose active', 'quantity': 10, 'unit': 'mg'},
        {'name': 'Blend child', 'quantity': null, 'unit': ''},
      ],
      blends: const [
        {
          'name': 'Actual Blend',
          'total_weight': 100,
          'unit': 'mg',
          'child_ingredients': [
            {'name': 'Blend child', 'amount': null, 'unit': ''},
          ],
        },
      ],
      disclosureTargetKey: targetKey,
    );

    expect(find.byKey(targetKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(targetKey),
        matching: find.text('Actual Blend'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(targetKey),
        matching: find.text('Proprietary blend'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(targetKey),
        matching: find.text('Loose active'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'same true reveal signal does not reopen after a manual collapse',
    (tester) async {
      final targetKey = GlobalKey();
      final revealSignal = ValueNotifier<bool>(true);
      addTearDown(revealSignal.dispose);
      late StateSetter rebuildParent;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuildParent = setState;
                return buildIngredientsSection(
                  context: context,
                  ingredients: [
                    for (var index = 0; index < 6; index++)
                      {'name': 'Ingredient $index'},
                  ],
                  inactiveIngredients: const [],
                  ulAnalysis: const [],
                  blends: const [],
                  disclosureTargetKey: targetKey,
                  disclosureRevealSignal: revealSignal,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(targetKey.currentContext, isNotNull);

      await tester.tap(find.text('What the label lists'));
      await tester.pumpAndSettle();
      expect(targetKey.currentContext, isNull);

      rebuildParent(() {});
      await tester.pumpAndSettle();

      expect(targetKey.currentContext, isNull);
    },
  );

  testWidgets(
    'same true reveal keeps a target beyond row 20 mounted after tile updates',
    (tester) async {
      final targetKey = GlobalKey();
      final revealSignal = ValueNotifier<bool>(true);
      addTearDown(revealSignal.dispose);
      late StateSetter rebuildParent;
      var ordinaryIngredientCount = 21;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuildParent = setState;
                return SingleChildScrollView(
                  child: buildIngredientsSection(
                    context: context,
                    ingredients: const [],
                    displayIngredients: [
                      for (
                        var index = 0;
                        index < ordinaryIngredientCount;
                        index++
                      )
                        {'label_display_name': 'Ordinary active $index'},
                      {
                        'display_type': 'structural_container',
                        'label_display_name': 'Target beyond row 20',
                        'children': const ['Blend child'],
                      },
                    ],
                    inactiveIngredients: const [],
                    ulAnalysis: const [],
                    blends: const [],
                    disclosureTargetKey: targetKey,
                    disclosureRevealSignal: revealSignal,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(targetKey.currentContext, isNotNull);

      rebuildParent(() => ordinaryIngredientCount = 22);
      await tester.pumpAndSettle();

      expect(targetKey.currentContext, isNotNull);
      expect(find.byKey(targetKey), findsOneWidget);
    },
  );

  testWidgets('reveal listener swaps and unregisters on dispose', (
    tester,
  ) async {
    final targetKey = GlobalKey();
    final firstSignal = _RevealSignal();
    final secondSignal = _RevealSignal();
    secondSignal.reveal();
    addTearDown(firstSignal.dispose);
    addTearDown(secondSignal.dispose);
    late StateSetter rebuild;
    var signal = firstSignal;
    var ingredientCount = 6;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return buildIngredientsSection(
                context: context,
                ingredients: [
                  for (var index = 0; index < ingredientCount; index++)
                    {'name': 'Ingredient $index'},
                ],
                inactiveIngredients: const [],
                ulAnalysis: const [],
                blends: const [],
                disclosureTargetKey: targetKey,
                disclosureRevealSignal: signal,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(targetKey.currentContext, isNull);

    rebuild(() => signal = secondSignal);
    await tester.pumpAndSettle();
    expect(targetKey.currentContext, isNotNull);

    await tester.tap(find.text('What the label lists'));
    await tester.pumpAndSettle();
    expect(targetKey.currentContext, isNull);

    firstSignal.reveal();
    await tester.pumpAndSettle();
    expect(targetKey.currentContext, isNull);

    secondSignal.value = false;
    await tester.pumpAndSettle();
    expect(targetKey.currentContext, isNull);

    secondSignal.reveal();
    await tester.pumpAndSettle();
    expect(targetKey.currentContext, isNotNull);

    rebuild(() => ingredientCount = 7);
    await tester.pumpAndSettle();
    expect(targetKey.currentContext, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    secondSignal.value = false;
    secondSignal.reveal();
    await tester.pump();
    expect(tester.takeException(), isNull);
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

Future<void> _pumpIngredients(
  WidgetTester tester, {
  List<Map<String, dynamic>> ingredients = const [],
  List<Map<String, dynamic>>? displayIngredients,
  List<Map<String, dynamic>> blends = const [],
  GlobalKey? disclosureTargetKey,
  ValueListenable<bool>? disclosureRevealSignal,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => SingleChildScrollView(
            child: buildIngredientsSection(
              context: context,
              ingredients: ingredients,
              displayIngredients: displayIngredients,
              inactiveIngredients: const [],
              ulAnalysis: const [],
              blends: blends,
              disclosureTargetKey: disclosureTargetKey,
              disclosureRevealSignal: disclosureRevealSignal,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _RevealSignal extends ValueNotifier<bool> {
  _RevealSignal() : super(false);

  void reveal() => value = true;
}
