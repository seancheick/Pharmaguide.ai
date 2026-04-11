// Tests for [StackNutrientAggregator].
//
// The aggregator is a pure function, so every test is a direct
// input/output assertion with no mocks. Each test exercises one
// contract clause from the aggregator doc. When a pipeline schema
// drift is found in production, add a regression here first, then
// fix.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

void main() {
  const aggregator = StackNutrientAggregator();

  group('StackNutrientAggregator — empty & trivial cases', () {
    test('empty stack returns empty map', () {
      final result = aggregator.aggregate([]);
      expect(result, isEmpty);
    });

    test('single product with single ingredient produces single total',
        () {
      final stack = [
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Thorne D/K2',
          ingredients: [
            {
              'mapped_name': 'vitamin_d3',
              'name': 'Vitamin D3 (Cholecalciferol)',
              'amount': 2000,
              'unit': 'IU',
              'is_active': true,
            },
          ],
        ),
      ];
      final result = aggregator.aggregate(stack);
      expect(result, hasLength(1));
      final vd3 = result['vitamin_d3']!;
      expect(vd3.totalAmount, 2000);
      expect(vd3.unit, 'iu');
      expect(vd3.displayName, 'Vitamin D3 (Cholecalciferol)');
      expect(vd3.contributions, hasLength(1));
      expect(vd3.contributions.first.productName, 'Thorne D/K2');
      expect(vd3.hasUnitConflict, isFalse);
    });
  });

  group('StackNutrientAggregator — summation across products', () {
    test('two products with same nutrient sum cleanly', () {
      final stack = [
        _productOf('s1', 'Thorne D3', [
          {
            'mapped_name': 'vitamin_d3',
            'name': 'Vitamin D3',
            'amount': 2000,
            'unit': 'IU',
            'is_active': true,
          },
        ]),
        _productOf('s2', 'Pure D3', [
          {
            'mapped_name': 'vitamin_d3',
            'name': 'Cholecalciferol',
            'amount': 1000,
            'unit': 'IU',
            'is_active': true,
          },
        ]),
      ];
      final result = aggregator.aggregate(stack);
      expect(result['vitamin_d3']!.totalAmount, 3000);
      expect(result['vitamin_d3']!.contributions, hasLength(2));
      expect(
        result['vitamin_d3']!.contributions.map((c) => c.productName),
        containsAll(['Thorne D3', 'Pure D3']),
      );
    });

    test('multiple nutrients across multiple products aggregate independently',
        () {
      final stack = [
        _productOf('s1', 'Multi A', [
          _ing('zinc', 'Zinc', 15, 'mg'),
          _ing('magnesium', 'Magnesium', 200, 'mg'),
        ]),
        _productOf('s2', 'Immune', [
          _ing('zinc', 'Zinc (Picolinate)', 22, 'mg'),
          _ing('vitamin_c', 'Vitamin C', 500, 'mg'),
        ]),
        _productOf('s3', 'Zinc Supplement', [
          _ing('zinc', 'Zinc', 15, 'mg'),
        ]),
      ];
      final result = aggregator.aggregate(stack);
      expect(result, hasLength(3));
      expect(result['zinc']!.totalAmount, 52);
      expect(result['zinc']!.contributions, hasLength(3));
      expect(result['magnesium']!.totalAmount, 200);
      expect(result['vitamin_c']!.totalAmount, 500);
    });

    test('zinc stacking example matches spec — 52mg from 3 products', () {
      // From the spec's UX mockup. This exact scenario is the reason
      // M1 exists: per-product UL checks miss the accumulation.
      final stack = [
        _productOf('multi', 'Multi A', [_ing('zinc', 'Zinc', 15, 'mg')]),
        _productOf('immune', 'Immune Support',
            [_ing('zinc', 'Zinc', 22, 'mg')]),
        _productOf(
            'zinc_pico', 'Zinc Picolinate', [_ing('zinc', 'Zinc', 15, 'mg')]),
      ];
      final total = aggregator.aggregate(stack)['zinc']!;
      expect(total.totalAmount, 52);
    });
  });

  group('StackNutrientAggregator — field-name fallbacks', () {
    test('reads canonical_id when mapped_name is absent', () {
      final stack = [
        _productOf('s1', 'X', [
          {
            'canonical_id': 'iron',
            'name': 'Iron',
            'amount': 10,
            'unit': 'mg',
          },
        ]),
      ];
      expect(aggregator.aggregate(stack)['iron']!.totalAmount, 10);
    });

    test('reads standard_name when canonical_id and mapped_name are absent',
        () {
      final stack = [
        _productOf('s1', 'X', [
          {
            'standard_name': 'Magnesium',
            'name': 'Mg',
            'amount': 200,
            'unit': 'mg',
          },
        ]),
      ];
      expect(aggregator.aggregate(stack)['magnesium']!.totalAmount, 200);
    });

    test('reads normalizedAmount (camelCase) when amount is absent', () {
      final stack = [
        _productOf('s1', 'X', [
          {
            'mapped_name': 'vitamin_b12',
            'name': 'B12',
            'normalizedAmount': 500,
            'normalizedUnit': 'mcg',
          },
        ]),
      ];
      expect(aggregator.aggregate(stack)['vitamin_b12']!.totalAmount, 500);
      expect(aggregator.aggregate(stack)['vitamin_b12']!.unit, 'mcg');
    });

    test('reads quantity when amount is absent', () {
      final stack = [
        _productOf('s1', 'X', [
          {
            'mapped_name': 'vitamin_d3',
            'name': 'D3',
            'quantity': 2000,
            'unit': 'IU',
          },
        ]),
      ];
      expect(aggregator.aggregate(stack)['vitamin_d3']!.totalAmount, 2000);
    });

    test('parses amount from int, double, and numeric string uniformly', () {
      final stack = [
        _productOf('s1', 'Int', [
          {'mapped_name': 'iron', 'name': 'Iron', 'amount': 5, 'unit': 'mg'}
        ]),
        _productOf('s2', 'Double', [
          {
            'mapped_name': 'iron',
            'name': 'Iron',
            'amount': 2.5,
            'unit': 'mg'
          }
        ]),
        _productOf('s3', 'String', [
          {
            'mapped_name': 'iron',
            'name': 'Iron',
            'amount': '7.5',
            'unit': 'mg'
          }
        ]),
      ];
      expect(aggregator.aggregate(stack)['iron']!.totalAmount, 15);
    });

    test('case-insensitive canonical matching merges uppercase and lowercase',
        () {
      final stack = [
        _productOf('s1', 'A',
            [_ing('Zinc', 'Zinc', 10, 'mg', keyField: 'mapped_name')]),
        _productOf('s2', 'B',
            [_ing('ZINC', 'Zinc', 15, 'mg', keyField: 'mapped_name')]),
        _productOf('s3', 'C',
            [_ing('zinc', 'Zinc', 5, 'mg', keyField: 'mapped_name')]),
      ];
      final result = aggregator.aggregate(stack);
      expect(result.keys, hasLength(1));
      expect(result['zinc']!.totalAmount, 30);
    });
  });

  group('StackNutrientAggregator — skip rules', () {
    test('skips rows with no canonical id', () {
      final stack = [
        _productOf('s1', 'Mystery', [
          {
            'name': 'Proprietary Blend',
            'amount': 500,
            'unit': 'mg',
          },
        ]),
      ];
      expect(aggregator.aggregate(stack), isEmpty);
    });

    test('skips rows with no numeric amount', () {
      final stack = [
        _productOf('s1', 'X', [
          {
            'mapped_name': 'vitamin_c',
            'name': 'Vitamin C',
            'amount': null,
            'unit': 'mg',
          },
        ]),
      ];
      expect(aggregator.aggregate(stack), isEmpty);
    });

    test('skips rows with zero or negative amount', () {
      final stack = [
        _productOf('s1', 'X', [
          _ing('iron', 'Iron', 0, 'mg'),
          _ing('zinc', 'Zinc', -5, 'mg'),
          _ing('magnesium', 'Magnesium', 100, 'mg'),
        ]),
      ];
      final result = aggregator.aggregate(stack);
      expect(result.keys, equals({'magnesium'}));
    });

    test('skips rows with is_active: false', () {
      final stack = [
        _productOf('s1', 'X', [
          {
            'mapped_name': 'iron',
            'name': 'Iron',
            'amount': 10,
            'unit': 'mg',
            'is_active': false,
          },
          _ing('zinc', 'Zinc', 15, 'mg'),
        ]),
      ];
      final result = aggregator.aggregate(stack);
      expect(result.containsKey('iron'), isFalse);
      expect(result['zinc']!.totalAmount, 15);
    });

    test('skips proprietary blend container rows', () {
      final stack = [
        _productOf('s1', 'Blend Product', [
          {
            'mapped_name': 'energy_blend',
            'name': 'Energy Blend',
            'amount': 500,
            'unit': 'mg',
            'is_proprietary_blend': true,
          },
          _ing('caffeine', 'Caffeine', 200, 'mg'),
        ]),
      ];
      final result = aggregator.aggregate(stack);
      expect(result.containsKey('energy_blend'), isFalse);
      expect(result['caffeine']!.totalAmount, 200);
    });

    test('skips parent-total rows in nested nutrient trees', () {
      final stack = [
        _productOf('s1', 'Vitamin A Complex', [
          {
            'mapped_name': 'vitamin_a',
            'name': 'Vitamin A (total)',
            'amount': 10000,
            'unit': 'IU',
            'is_parent_total': true,
          },
          _ing('beta_carotene', 'Beta-Carotene', 8000, 'IU'),
          _ing('retinyl_palmitate', 'Retinyl Palmitate', 2000, 'IU'),
        ]),
      ];
      final result = aggregator.aggregate(stack);
      expect(result.containsKey('vitamin_a'), isFalse);
      expect(result['beta_carotene']!.totalAmount, 8000);
      expect(result['retinyl_palmitate']!.totalAmount, 2000);
    });

    test('treats missing is_active as active (default-safe)', () {
      // A lot of legacy blobs simply omit the flag. Those rows must
      // still count.
      final stack = [
        _productOf('s1', 'X', [
          {
            'mapped_name': 'vitamin_c',
            'name': 'Vitamin C',
            'amount': 500,
            'unit': 'mg',
          },
        ]),
      ];
      expect(aggregator.aggregate(stack)['vitamin_c']!.totalAmount, 500);
    });
  });

  group('StackNutrientAggregator — unit conflict handling', () {
    test('mismatched units flag the total and sum only matching contributions',
        () {
      final stack = [
        _productOf('s1', 'Folate A', [_ing('folate', 'Folate', 400, 'mcg')]),
        _productOf('s2', 'Folate B', [_ing('folate', 'Folate', 800, 'mcg')]),
        _productOf('s3', 'Folate C (weird)',
            [_ing('folate', 'Folate', 1, 'mg')]),
      ];
      final total = aggregator.aggregate(stack)['folate']!;
      // First-seen unit is mcg, so only the two mcg contributions sum.
      expect(total.unit, 'mcg');
      expect(total.totalAmount, 1200);
      expect(total.hasUnitConflict, isTrue);
      // All three contributions appear for UI transparency.
      expect(total.contributions, hasLength(3));
    });

    test('missing unit on one contribution matches any other unit', () {
      // Intentionally loose: prefer to sum rather than drop a row just
      // because the unit field is blank.
      final stack = [
        _productOf('s1', 'A', [_ing('iron', 'Iron', 10, 'mg')]),
        _productOf('s2', 'B', [
          {
            'mapped_name': 'iron',
            'name': 'Iron',
            'amount': 5,
            // unit omitted entirely
          },
        ]),
      ];
      final total = aggregator.aggregate(stack)['iron']!;
      expect(total.totalAmount, 15);
      expect(total.hasUnitConflict, isFalse);
    });
  });

  group('StackNutrientAggregator — display name preference', () {
    test('keeps the longest display name across contributions', () {
      final stack = [
        _productOf('s1', 'A', [_ing('vitamin_d3', 'D3', 1000, 'IU')]),
        _productOf('s2', 'B',
            [_ing('vitamin_d3', 'Vitamin D3 (Cholecalciferol)', 2000, 'IU')]),
        _productOf('s3', 'C', [_ing('vitamin_d3', 'Vitamin D', 1000, 'IU')]),
      ];
      final total = aggregator.aggregate(stack)['vitamin_d3']!;
      expect(total.displayName, 'Vitamin D3 (Cholecalciferol)');
    });
  });
}

/// Helper: build a [StackItemNutrients] with a readable arg order.
StackItemNutrients _productOf(
  String id,
  String name,
  List<Map<String, dynamic>> ingredients,
) =>
    StackItemNutrients(
      stackEntryId: id,
      productName: name,
      ingredients: ingredients,
    );

/// Helper: build a single ingredient row.
Map<String, dynamic> _ing(
  String canonical,
  String display,
  num amount,
  String unit, {
  String keyField = 'mapped_name',
}) =>
    {
      keyField: canonical,
      'name': display,
      'amount': amount,
      'unit': unit,
      'is_active': true,
    };
