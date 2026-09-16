// Layout regressions from the 2026-09-16 DS-01 Daily Synbiotic walkthrough:
// blend amounts read "Amount not disclosed" beside a grey "Serving amounts"
// box, the Active ingredients badge said 1 for 24 strains, blend names and
// Other ingredient names were cut off, and strain rows were heavy.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_inactive_row.dart';
import 'package:pharmaguide/core/components/pg_ingredient_tile.dart';
import 'package:pharmaguide/core/components/pg_ingredients_card.dart';
import 'package:pharmaguide/core/data/functional_roles_vocab.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/ingredients_section.dart';

// DS-01 shape: the label gives each blend one amount in two units for the
// same serving, so both variants carry no serving identity.
const _ds01Rows = <Map<String, dynamic>>[
  {
    'label_display_name': 'Digestive Health Probiotic Blend',
    'display_type': 'structural_container',
    'display_disposition': 'label_context',
    'nested_depth': 0,
    'exact_dose_text': '',
    'raw_source_path': 'ingredientRows[0]',
    'children': ['B. longum SD-BB536-JP', 'B. breve SD-BR3-IT'],
    'serving_variants': [
      {
        'serving_size_order': null,
        'serving_size_quantity': null,
        'serving_size_unit': '',
        'exact_dose_text': '206 mg',
        'is_canonical': false,
      },
      {
        'serving_size_order': null,
        'serving_size_quantity': null,
        'serving_size_unit': '',
        'exact_dose_text': '37 Billion AFU',
        'is_canonical': false,
      },
    ],
  },
  {
    'label_display_name': 'B. longum SD-BB536-JP',
    'nested_depth': 1,
    'parent_label': 'Digestive Health Probiotic Blend',
    'parent_source_path': 'ingredientRows[0]',
    'raw_source_path': 'ingredientRows[0].nestedRows[0]',
    'form_display_state': 'not_applicable',
  },
  {
    'label_display_name': 'B. breve SD-BR3-IT',
    'nested_depth': 1,
    'parent_label': 'Digestive Health Probiotic Blend',
    'parent_source_path': 'ingredientRows[0]',
    'raw_source_path': 'ingredientRows[0].nestedRows[1]',
    'form_display_state': 'not_applicable',
  },
  {
    'label_display_name': 'Micronutrient Synthesis Probiotic Blend',
    'display_type': 'structural_container',
    'display_disposition': 'label_context',
    'nested_depth': 0,
    'exact_dose_text': '',
    'raw_source_path': 'ingredientRows[1]',
    'children': ['L. reuteri SD-LRE2-IT'],
  },
  {
    'label_display_name': 'L. reuteri SD-LRE2-IT',
    'nested_depth': 1,
    'parent_label': 'Micronutrient Synthesis Probiotic Blend',
    'parent_source_path': 'ingredientRows[1]',
    'raw_source_path': 'ingredientRows[1].nestedRows[0]',
    'form_display_state': 'not_applicable',
  },
  {
    'label_display_name': 'MAPP Microbiota-Accessible Polyphenolic Precursors',
    'display_type': 'mapped_ingredient',
    'nested_depth': 0,
    'exact_dose_text': '400 mg',
    'raw_source_path': 'ingredientRows[4]',
  },
  {
    'label_display_name':
        'Acid-Resistant Vegan Outer [chlorophyllin] and Inner '
        '[hypromellose, water] Capsules',
    'display_type': 'inactive_ingredient',
    'display_disposition': 'other_ingredient',
    'nested_depth': 0,
    'raw_source_path': 'otheringredients.ingredients[0]',
  },
  {
    'label_display_name': 'organic rice extract blend.',
    'display_type': 'inactive_ingredient',
    'display_disposition': 'other_ingredient',
    'nested_depth': 0,
    'raw_source_path': 'otheringredients.ingredients[1]',
  },
];

Future<void> _pumpDs01(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: buildIngredientsSection(
                context: ctx,
                ingredients: const [],
                displayIngredients: _ds01Rows,
                inactiveIngredients: const [],
                ulAnalysis: const [],
                blends: const [],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => debugSetFunctionalRolesVocabForTesting({}));
  tearDown(() => debugSetFunctionalRolesVocabForTesting(null));

  testWidgets('one amount given in two units is the blend amount', (
    tester,
  ) async {
    await _pumpDs01(tester);

    expect(find.text('37 Billion AFU · 206 mg'), findsOneWidget);
    expect(find.text('Serving amounts on label'), findsNothing);
    // Only the Micronutrient blend, which lists no amount, says so.
    expect(find.text('Amount not disclosed'), findsOneWidget);
  });

  testWidgets('Active ingredients badge counts strains inside blends', (
    tester,
  ) async {
    await _pumpDs01(tester);

    final badge = find.descendant(
      of: find.ancestor(
        of: find.text('Active ingredients'),
        matching: find.byType(Row),
      ),
      matching: find.text('4'),
    );
    expect(badge, findsOneWidget);
  });

  testWidgets('strain rows inside a blend are compact and undivided', (
    tester,
  ) async {
    await _pumpDs01(tester);

    final strain = tester.widget<PGActiveIngredientTile>(
      find.ancestor(
        of: find.text('B. longum SD-BB536-JP'),
        matching: find.byType(PGActiveIngredientTile),
      ),
    );
    expect(strain.showBottomDivider, isFalse);
    expect(strain.dense, isTrue);
  });

  testWidgets('long blend names are not cut off on a phone', (tester) async {
    await _pumpDs01(tester);

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Micronutrient Synthesis Probiotic Blend'),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  testWidgets('Other ingredients wrap and drop trailing label punctuation', (
    tester,
  ) async {
    await _pumpDs01(tester);

    expect(find.text('Organic rice extract blend'), findsOneWidget);
    final capsule = find.descendant(
      of: find.byType(PGInactiveRow),
      matching: find.textContaining('Acid-Resistant Vegan Outer'),
    );
    expect(
      tester.renderObject<RenderParagraph>(capsule).didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('a blend inside a blend is a sub-heading, not an ingredient', (
    tester,
  ) async {
    // Fortify shape: top blend -> "Lactobacilli Blend" -> strains.
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
                    'label_display_name': 'Women’s Probiotic Blend',
                    'display_type': 'structural_container',
                    'nested_depth': 0,
                    'exact_dose_text': '530 mg',
                    'raw_source_path': 'ingredientRows[0]',
                    'children': ['Lactobacilli Blend'],
                  },
                  {
                    'label_display_name': 'Lactobacilli Blend',
                    'display_type': 'structural_container',
                    'nested_depth': 1,
                    'parent_label': 'Women’s Probiotic Blend',
                    'parent_source_path': 'ingredientRows[0]',
                    'raw_source_path': 'ingredientRows[0].nestedRows[0]',
                  },
                  {
                    'label_display_name': 'L. rhamnosus GG',
                    'display_type': 'mapped_ingredient',
                    'nested_depth': 2,
                    'parent_label': 'Lactobacilli Blend',
                    'parent_source_path': 'ingredientRows[0].nestedRows[0]',
                    'raw_source_path': 'ingredientRows[0].nestedRows[0].x',
                    'form_display_state': 'not_applicable',
                  },
                  {
                    'label_display_name': 'Chicory Root Fiber',
                    'display_type': 'mapped_ingredient',
                    'nested_depth': 0,
                    'exact_dose_text': '50 mg',
                    'raw_source_path': 'ingredientRows[1]',
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

    expect(find.text('Lactobacilli Blend'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Lactobacilli Blend'),
        matching: find.byType(PGActiveIngredientTile),
      ),
      findsNothing,
    );
    final badge = find.descendant(
      of: find.ancestor(
        of: find.text('Active ingredients'),
        matching: find.byType(Row),
      ),
      matching: find.text('2'),
    );
    expect(badge, findsOneWidget);
  });

  testWidgets('Show more never splits a blend from its strains', (
    tester,
  ) async {
    // DS-01: the 20-row reveal chunk ended inside "Micronutrient Synthesis
    // Probiotic Blend", showing one of its two strains above "Show more".
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PGActiveIngredientsSection(
              tiles: [
                for (var i = 0; i < 19; i++) Text('row $i'),
                const Text('Blend header'),
                const PGNestedIngredientRow(child: Text('strain a')),
                const PGNestedIngredientRow(child: Text('strain b')),
                const Text('after the blend'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('strain b'), findsOneWidget);
    expect(find.text('after the blend'), findsNothing);
    expect(find.text('Show more'), findsOneWidget);
  });

  test('label display cleanup keeps chemistry prefixes intact', () {
    expect(cleanLabelDisplayName('organic rice fiber'), 'Organic rice fiber');
    expect(cleanLabelDisplayName('rice extract blend.'), 'Rice extract blend');
    expect(cleanLabelDisplayName('d-alpha tocopherol'), 'd-alpha tocopherol');
    expect(cleanLabelDisplayName('dl-malic acid'), 'dl-malic acid');
    expect(cleanLabelDisplayName('pH buffer'), 'pH buffer');
    expect(cleanLabelDisplayName('Hypromellose'), 'Hypromellose');
  });
}
