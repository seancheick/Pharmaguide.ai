import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';

void main() {
  group('extractIngredientDoses', () {
    test('null blob -> empty map', () {
      expect(extractIngredientDoses(null), isEmpty);
    });

    test('blob without ingredients key -> empty map', () {
      expect(extractIngredientDoses({'foo': 'bar'}), isEmpty);
    });

    test('extracts canonical -> (value, unit) for valid entries', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Vitamin D3', 'dose_amount': 1000, 'dose_unit': 'IU'},
          {
            'name': 'Magnesium glycinate',
            'dose_amount': 200,
            'dose_unit': 'mg',
          },
        ],
      });

      expect(result, hasLength(2));
      expect(result['vitamin_d3'], (value: 1000.0, unit: 'IU'));
      expect(result['magnesium_glycinate'], (value: 200.0, unit: 'mg'));
    });

    test('extracts live pipeline quantity / unit field names', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Alpha Lipoic Acid', 'quantity': 350, 'unit': 'mg'},
          {'name': 'Vanadium', 'quantity': 50, 'unit': 'mcg'},
          {'name': 'Niacin', 'quantity': 37.5, 'unit': 'mg'},
        ],
      });

      expect(result, hasLength(3));
      expect(result['alpha_lipoic_acid'], (value: 350.0, unit: 'mg'));
      expect(result['vanadium'], (value: 50.0, unit: 'mcg'));
      expect(result['niacin'], (value: 37.5, unit: 'mg'));
    });

    test('extracts dose rows from rda_ul_data when ingredients are absent', () {
      final result = extractIngredientDoses({
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Alpha Lipoic Acid',
              'quantity': 350,
              'daily_amount_unit': 'mg',
            },
            {
              'standard_name': 'Vanadium',
              'quantity': '50',
              'daily_amount_unit': 'mcg',
            },
          ],
        },
      });

      expect(result['alpha_lipoic_acid'], (value: 350.0, unit: 'mg'));
      expect(result['vanadium'], (value: 50.0, unit: 'mcg'));
    });

    test('skips rda_ul_data rows marked unsafe for UL evaluation', () {
      final result = extractIngredientDoses({
        'rda_ul_data': {
          'analyzed_ingredients': [
            {
              'standard_name': 'Vitamin A',
              'quantity': 2000,
              'daily_amount_unit': 'IU',
              'skip_ul_check': true,
            },
          ],
        },
      });

      expect(result, isEmpty);
    });

    test('live quantity field wins over stale dose_amount mirror', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {
            'name': 'Iodine',
            'quantity': 100,
            'unit': 'mcg',
            'dose_amount': 999,
            'dose_unit': 'IU',
          },
        ],
      });

      expect(result['iodine'], (value: 100.0, unit: 'mcg'));
    });

    test('sums duplicate canonical dose rows when units match', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Caffeine', 'quantity': 80, 'unit': 'mg'},
          {'name': 'Caffeine', 'quantity': 60, 'unit': 'mg'},
        ],
      });

      expect(result['caffeine'], (value: 140.0, unit: 'mg'));
    });

    test('sums duplicate canonical dose rows across simple mass units', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Alpha Lipoic Acid', 'quantity': 0.3, 'unit': 'g'},
          {'name': 'Alpha Lipoic Acid', 'quantity': 300, 'unit': 'mg'},
        ],
      });

      expect(result['alpha_lipoic_acid'], (value: 0.6, unit: 'g'));
    });

    test('drops duplicate canonical dose rows with incompatible units', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Vitamin A', 'quantity': 3000, 'unit': 'IU'},
          {'name': 'Vitamin A', 'quantity': 900, 'unit': 'mcg RAE'},
        ],
      });

      expect(result.containsKey('vitamin_a'), isFalse);
    });

    test('parses string-typed dose amount defensively', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {'name': 'Iron', 'dose_amount': '18', 'dose_unit': 'mg'},
        ],
      });

      expect(result['iron']?.value, 18.0);
    });
  });

  group('extractIngredientDoses - elemental vs compound dedup', () {
    test('mirrored elemental + compound rows use only elemental value', () {
      final magnesiumRows = [
        {
          'name': 'Magnesium',
          'canonical_id': 'magnesium',
          'quantity': 60,
          'unit': 'mg',
        },
        {
          'name': 'Magnesium Glycinate',
          'canonical_id': 'magnesium',
          'quantity': 400,
          'unit': 'mg',
        },
      ];

      final result = extractIngredientDoses({
        'ingredients': magnesiumRows,
        'rda_ul_data': {'analyzed_ingredients': magnesiumRows},
      });

      expect(result['magnesium'], (value: 60.0, unit: 'mg'));
      expect(result['magnesium_glycinate'], (value: 400.0, unit: 'mg'));
    });

    test('elemental parenthetical counts as elemental row', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {
            'name': 'Magnesium (elemental)',
            'canonical_id': 'magnesium',
            'quantity': 60,
            'unit': 'mg',
          },
          {
            'name': 'Magnesium Glycinate',
            'canonical_id': 'magnesium',
            'quantity': 400,
            'unit': 'mg',
          },
        ],
      });

      expect(result['magnesium']?.value, 60.0);
    });

    test('multi-form rows with no bare elemental row legitimately sum', () {
      final result = extractIngredientDoses({
        'ingredients': [
          {
            'name': 'Magnesium (as oxide)',
            'mapped_name': 'magnesium',
            'quantity': 200,
            'unit': 'mg',
          },
          {
            'name': 'Magnesium (as citrate)',
            'mapped_name': 'magnesium',
            'quantity': 100,
            'unit': 'mg',
          },
        ],
      });

      expect(result['magnesium'], (value: 300.0, unit: 'mg'));
    });
  });

  group('parseBlobWarnings - structured allergen contract', () {
    test(
      'drops duplicate allergen warnings when structured allergens exist',
      () {
        final result = parseBlobWarnings({
          'allergens': [
            {
              'allergen_id': 'ALLERGEN_BARLEY',
              'display_name': 'Barley',
              'presence_type': 'ingredient_list',
            },
          ],
          'warnings': [
            {
              'type': 'allergen',
              'source': 'allergen_db',
              'severity': 'caution',
              'title': 'Allergen: Barley',
              'detail': 'Presence: ingredient_list',
            },
          ],
          'warnings_profile_gated': [
            {
              'type': 'allergen',
              'source': 'allergen_db',
              'severity': 'caution',
              'title': 'Allergen: Wheat',
              'detail': 'Presence: ingredient_list',
            },
          ],
        });

        expect(result, isEmpty);
      },
    );

    test('keeps legacy allergen warning when structured id is absent', () {
      final result = parseBlobWarnings({
        'allergens': [
          {'display_name': 'Milk', 'presence_type': 'contains'},
        ],
        'warnings': [
          {
            'type': 'allergen',
            'source': 'allergen_db',
            'severity': 'caution',
            'title': 'Allergen: Milk',
            'detail': 'Presence: contains',
          },
        ],
      });

      expect(result, hasLength(1));
      expect(result.single.title, 'Allergen: Milk');
    });

    test(
      'keeps legacy allergen warnings when structured allergens are absent',
      () {
        final result = parseBlobWarnings({
          'warnings': [
            {
              'type': 'allergen',
              'source': 'allergen_db',
              'severity': 'caution',
              'title': 'Allergen: Barley',
              'detail': 'Presence: ingredient_list',
            },
          ],
        });

        expect(result, hasLength(1));
        expect(result.single.title, 'Allergen: Barley');
      },
    );
  });
}
