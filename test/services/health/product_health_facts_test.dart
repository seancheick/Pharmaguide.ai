import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/health/product_health_facts.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

void main() {
  test('service-layer warning facade exposes the pipeline warning model', () {
    final warning = InteractionWarning.fromJson({
      'severity': 'avoid',
      'evidence_level': 'theoretical',
      'title': 'Pregnancy warning',
      'detail': 'Review before use.',
      'condition_ids': ['pregnancy'],
    });

    expect(warning.severity, Severity.avoid);
    expect(warning.conditionIds, ['pregnancy']);
  });

  test(
    'warning model is owned by the service layer, not product UI widgets',
    () {
      final serviceModel = File(
        'lib/services/warnings/interaction_warning.dart',
      ).readAsStringSync();
      final widgetFile = File(
        'lib/features/product_detail/widgets/interaction_warnings.dart',
      ).readAsStringSync();

      expect(
        serviceModel,
        isNot(contains('features/product_detail/widgets/interaction_warnings')),
      );
      expect(
        widgetFile,
        contains('services/warnings/interaction_warning.dart'),
      );
      expect(widgetFile, isNot(contains('class InteractionWarning')));
    },
  );

  test('model-only product-detail collaborators import the service model', () {
    for (final path in const [
      'lib/features/product_detail/providers/personalized_warnings_provider.dart',
      'lib/features/product_detail/v2/sections/populations_section.dart',
      'lib/features/product_detail/v2/sections/review_before_use_section.dart',
      'lib/features/product_detail/v2/sections/review_before_use_helpers.dart',
      'lib/features/product_detail/v2/product_detail_v2_connected.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('services/warnings/interaction_warning.dart'),
        reason: path,
      );
      expect(
        source,
        isNot(contains('features/product_detail/widgets/interaction_warnings')),
        reason: path,
      );
    }
  });

  group('ProductHealthFacts.fromDetailBlob', () {
    test('uses pipeline RDA/UL rows before legacy ingredient fallbacks', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'ingredients': [
          {'name': 'Legacy Zinc', 'quantity': 15, 'unit': 'mg'},
        ],
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Zinc',
              'mapped_name': 'zinc',
              'per_day_max': 30,
              'daily_amount_unit': 'mg',
            },
          ],
        },
      });

      expect(facts.nutrients, hasLength(1));
      expect(facts.nutrients.single['standard_name'], 'Zinc');
      expect(facts.nutrients.single['per_day_max'], 30);
      expect(facts.activeIngredients.single['name'], 'Legacy Zinc');
      expect(facts.ulAnalysis.single['standard_name'], 'Zinc');
      expect(
        facts.ingredientContextRows.map((row) => row['standard_name']),
        contains('Zinc'),
      );
      expect(facts.ingredientNames, ['Zinc', 'Legacy Zinc']);
    });

    test('exposes active, inactive, and UL rows from one parsed boundary', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'ingredients': [
          {'name': 'Magnesium', 'quantity': 200, 'unit': 'mg'},
        ],
        'inactive_ingredients': [
          {
            'name': 'Cellulose',
            'functional_roles': ['binder'],
          },
        ],
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Magnesium',
              'mapped_name': 'magnesium',
              'per_day_max': 200,
              'daily_amount_unit': 'mg',
            },
          ],
        },
      });

      expect(facts.activeIngredients.single['name'], 'Magnesium');
      expect(facts.inactiveIngredients.single['name'], 'Cellulose');
      expect(facts.ulAnalysis.single['mapped_name'], 'magnesium');
      expect(facts.ingredientContextRows, hasLength(2));
      expect(facts.nutrients.single['standard_name'], 'Magnesium');
    });

    test(
      'ingredient context rows include ingredient-quality data even when RDA rows exist',
      () {
        final facts = ProductHealthFacts.fromDetailBlob({
          'rda_ul_data': {
            'analyzed_ingredients': [
              {'standard_name': 'Vitamin A', 'mapped_name': 'vitamin_a'},
            ],
          },
          'ingredient_quality_data': {
            'ingredients_scorable': [
              {'standard_name': 'Vitamin A', 'matched_form': 'beta_carotene'},
            ],
          },
        });

        expect(
          facts.ingredientContextRows.map((row) => row['matched_form']),
          contains('beta_carotene'),
        );
      },
    );

    test('feeds pipeline-converted nutrient rows into stack aggregation', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'ingredients': [
          {'mapped_name': 'vitamin_d', 'amount': 1000, 'unit': 'IU'},
        ],
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Vitamin D',
              'mapped_name': 'vitamin_d',
              'per_day_max': 25,
              'daily_amount_unit': 'mcg',
            },
          ],
        },
      });

      const aggregator = StackNutrientAggregator();
      final totals = aggregator.aggregate([
        StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Pipeline D',
          ingredients: facts.nutrients,
        ),
      ]);

      expect(totals['vitamin_d']!.totalAmount, 25);
      expect(totals['vitamin_d']!.unit, 'mcg');
    });

    test(
      'exposes canonical ingredient doses for condition threshold gates',
      () {
        final facts = ProductHealthFacts.fromDetailBlob({
          'ingredients': [
            {'name': 'Alpha-Lipoic Acid', 'quantity': 350, 'unit': 'mg'},
            {'name': 'Vanadium', 'dose_amount': '50', 'dose_unit': 'mcg'},
          ],
        });

        expect(facts.ingredientDoses['alpha_lipoic_acid']?.value, 350);
        expect(facts.ingredientDoses['alpha_lipoic_acid']?.unit, 'mg');
        expect(facts.ingredientDoses['vanadium']?.value, 50);
        expect(facts.ingredientDoses['vanadium']?.unit, 'mcg');
      },
    );

    test('exposes rda_ul_data doses for condition threshold gates', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Alpha Lipoic Acid',
              'quantity': 350,
              'daily_amount_unit': 'mg',
            },
          ],
        },
      });

      expect(facts.ingredientDoses['alpha_lipoic_acid']?.value, 350);
      expect(facts.ingredientDoses['alpha_lipoic_acid']?.unit, 'mg');
    });

    test('uses rda_ul_data names for personal-fit positive bullets', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Magnesium',
              'mapped_name': 'magnesium',
              'quantity': 200,
              'daily_amount_unit': 'mg',
            },
          ],
        },
      });

      expect(facts.ingredientNames, ['Magnesium']);
    });

    test('keeps non-RDA active names when rda_ul_data is present', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'ingredients': [
          {'name': 'Cinnamon Extract', 'quantity': 500, 'unit': 'mg'},
          {'name': 'Magnesium', 'quantity': 200, 'unit': 'mg'},
        ],
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Magnesium',
              'mapped_name': 'magnesium',
              'quantity': 200,
              'daily_amount_unit': 'mg',
            },
          ],
        },
      });

      expect(facts.nutrients, hasLength(1));
      expect(facts.nutrients.single['standard_name'], 'Magnesium');
      expect(facts.ingredientNames, ['Magnesium', 'Cinnamon Extract']);
    });

    test('falls back through known legacy ingredient shapes', () {
      final direct = ProductHealthFacts.fromDetailBlob({
        'ingredients': [
          {'name': 'Vitamin D', 'quantity': 25, 'unit': 'mcg'},
        ],
      });
      final nested = ProductHealthFacts.fromDetailBlob({
        'ingredient_quality_data': {
          'ingredients_scorable': [
            {'name': 'Iron', 'quantity': 18, 'unit': 'mg'},
          ],
        },
      });

      expect(direct.nutrients.single['name'], 'Vitamin D');
      expect(nested.nutrients.single['name'], 'Iron');
    });

    test(
      'falls through empty ingredient_quality_data.ingredients to populated ingredients_scorable',
      () {
        final facts = ProductHealthFacts.fromDetailBlob({
          'ingredient_quality_data': {
            'ingredients': <Object>[],
            'ingredients_scorable': [
              {'name': 'Cinnamon Extract', 'quantity': 500, 'unit': 'mg'},
            ],
          },
        });

        expect(facts.nutrients.single['name'], 'Cinnamon Extract');
        expect(facts.ingredientNames, ['Cinnamon Extract']);
      },
    );

    test('parses shared warning, interaction, allergen, and form facts', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'product_form': 'topical_only',
        'interaction_summary': {
          'condition_summary': [
            {'condition_id': 'pregnancy'},
          ],
        },
        'warnings': [
          {
            'severity': 'avoid',
            'evidence_level': 'theoretical',
            'title': 'Pregnancy warning',
            'detail': 'Avoid during pregnancy.',
            'action': 'Review with clinician.',
            'condition_ids': ['pregnancy'],
            'profile_gate': {
              'gate_type': 'condition',
              'requires': {
                'conditions_any': ['pregnancy'],
                'drug_classes_any': <String>[],
                'profile_flags_any': <String>[],
              },
              'excludes': {
                'conditions_any': <String>[],
                'drug_classes_any': <String>[],
                'profile_flags_any': <String>[],
                'product_forms_any': ['topical_only'],
                'nutrient_forms_any': <String>[],
              },
            },
          },
        ],
        'allergens': [
          {'id': 'ALLERGEN_SOY', 'presence_type': 'contains'},
        ],
        'product_clusters': ['sleep_support'],
      });

      expect(facts.productForm, 'topical_only');
      expect(
        facts.interactionSummary['condition_summary'],
        isA<List<dynamic>>(),
      );
      expect(facts.warnings, hasLength(1));
      expect(facts.warnings.single.severity, Severity.avoid);
      expect(facts.warnings.single.profileGate, isNotNull);
      expect(facts.allergens.single['id'], 'ALLERGEN_SOY');
      expect(facts.allergens.single['allergen_id'], 'ALLERGEN_SOY');
      expect(facts.productClusters, ['sleep_support']);
    });

    test('merges profile-gated warnings and removes duplicate entries', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'warnings': [
          {
            'severity': 'monitor',
            'title': 'Pregnancy warning',
            'detail': 'Review before use.',
            'condition_ids': ['pregnancy'],
          },
        ],
        'warnings_profile_gated': [
          {
            'severity': 'avoid',
            'title': 'Pregnancy warning',
            'detail': 'Review before use.',
            'condition_ids': ['pregnancy'],
          },
          {
            'severity': 'caution',
            'title': 'Kidney warning',
            'detail': 'Review before use.',
            'condition_ids': ['kidney_disease'],
          },
        ],
      });

      expect(facts.warnings, hasLength(2));
      expect(facts.warnings.first.title, 'Pregnancy warning');
      expect(facts.warnings.first.severity, Severity.avoid);
      expect(facts.warnings.last.title, 'Kidney warning');
    });

    test(
      'synthesizes UL exceedance warnings from pipeline RDA/UL analysis',
      () {
        final facts = ProductHealthFacts.fromDetailBlob({
          'rda_ul_data': {
            'analyzed_ingredients': [
              {
                'standard_name': 'Vitamin B3 (Niacin)',
                'skip_ul_check': false,
                'over_ul': true,
                'warnings': ['Exceeds UL by 15 mg'],
              },
              {
                'standard_name': 'Vitamin A',
                'skip_ul_check': true,
                'warnings': ['Skipped warning should not surface'],
              },
            ],
          },
        });

        expect(facts.warnings, hasLength(1));
        expect(
          facts.warnings.single.title,
          'Exceeds upper limit: Vitamin B3 (Niacin)',
        );
        expect(facts.warnings.single.mechanism, 'Exceeds UL by 15 mg');
        expect(facts.warnings.single.displayModeDefault, 'critical');
      },
    );

    test('does not synthesize UL warnings from stale prose alone', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Magtein',
              'quantity': 2000.0,
              'skip_ul_check': false,
              'pct_ul': null,
              'over_ul': null,
              'warnings': ['Exceeds UL by 1650.0 mg'],
            },
          ],
        },
      });

      expect(facts.warnings, isEmpty);
    });

    test('dedupes vitamin form and nutrient UL warnings', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Vitamin D3',
              'skip_ul_check': false,
              'over_ul': true,
              'warnings': ['Exceeds UL by 25 mcg'],
            },
            {
              'standard_name': 'Vitamin D',
              'skip_ul_check': false,
              'over_ul': true,
              'warnings': ['Exceeds UL by 25 mcg'],
            },
          ],
        },
      });

      expect(facts.warnings, hasLength(1));
      expect(facts.warnings.single.title, 'Exceeds upper limit: Vitamin D3');
    });

    test('UL dedupe ignores duplicate rows that have no warning payload', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Vitamin D3',
              'skip_ul_check': false,
              'warnings': <String>[],
            },
            {
              'standard_name': 'Vitamin D',
              'skip_ul_check': false,
              'over_ul': true,
              'warnings': ['Exceeds UL by 25 mcg'],
            },
          ],
        },
      });

      expect(facts.warnings, hasLength(1));
      expect(facts.warnings.single.title, 'Exceeds upper limit: Vitamin D');
    });

    test(
      'suppresses legacy product-status warnings when structured status exists',
      () {
        final facts = ProductHealthFacts.fromDetailBlob({
          'product_status': {'status': 'recalled'},
          'warnings': [
            {
              'severity': 'avoid',
              'title': 'Legacy status warning',
              'detail': 'Duplicated product status.',
              'type': 'product_status',
            },
            {
              'severity': 'avoid',
              'title': 'Interaction warning',
              'detail': 'Still health-relevant.',
              'drug_class_ids': ['anticoagulants'],
            },
          ],
        });

        expect(facts.warnings, hasLength(1));
        expect(facts.warnings.single.title, 'Interaction warning');
      },
    );

    test('extracts product clusters from current synergy detail shape', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'synergy_detail': {
          'clusters': [
            {'cluster_id': 'sleep_support'},
            {'cluster_id': 'stress_support'},
            {'cluster_id': 'sleep_support'},
            {'cluster_id': ''},
          ],
        },
      });

      expect(facts.productClusters, ['sleep_support', 'stress_support']);
    });

    test('keeps formulation_data synergy cluster fallback', () {
      final facts = ProductHealthFacts.fromDetailBlob({
        'formulation_data': {
          'synergy_clusters': [
            {'cluster_id': 'blood_sugar_support'},
          ],
        },
      });

      expect(facts.productClusters, ['blood_sugar_support']);
    });
  });
}
