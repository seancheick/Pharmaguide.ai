// Regression tests for the pipeline `ul_gate_eligible` contract in the
// stack nutrient aggregator.
//
// THE BUG (medical-grade over-warn)
//
// A single-form mineral compound product — e.g. Magtein
// "Magnesium L-Threonate 2000 mg" with NO separate bare-elemental
// "Magnesium" sibling row — carries the full 2000 mg COMPOUND mass on one
// row canonicalized to `magnesium`. The elemental-vs-compound dedup
// (`_compoundDuplicateRows`) only fires when an elemental SIBLING exists,
// so it misses the lone compound row. The client then compares 2000 mg of
// compound to the 350 mg ELEMENTAL magnesium UL → false 571% "exceeds UL".
//
// The pipeline now flags these rows with `ul_gate_eligible: false`
// (reason `compound_mass_not_elemental`). The aggregator must honor that
// decision and exclude the compound mass from the UL recompute, exactly
// as it already excludes an elemental-sibling compound duplicate.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_ul_checker.dart';

void main() {
  test('native four-label exports preserve unresolved dose in app totals', () {
    final fixtures =
        jsonDecode(
              File(
                'test/fixtures/label_unit_conflicts_20261012.json',
              ).readAsStringSync(),
            )
            as List;
    final rda =
        jsonDecode(
              File(
                'assets/reference_data/rda_optimal_uls.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    for (final fixture in fixtures) {
      final rows = (fixture['rows'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      final items = [
        StackItemNutrients(
          stackEntryId: fixture['id'] as String,
          productName: fixture['id'] as String,
          ingredients: rows,
        ),
      ];
      final totals = const StackNutrientAggregator().aggregate(items);
      final statuses = StackUlChecker(rdaData: rda).check(
        totals,
        ageBracket: '19-30',
        sex: 'Male',
        pipelineVerdicts: const StackNutrientAggregator()
            .extractPipelineUlVerdicts(items),
      );
      expect(statuses, hasLength(rows.length), reason: fixture['id'] as String);
      for (final status in statuses) {
        expect(status.ulAssessmentIndeterminate, isTrue);
        expect(status.pctOfUl, isNull);
        expect(status.pctOfRda, isNull);
        expect(status.total.contributions, isEmpty);
        expect(status.total.hasUnitConflict, isTrue);
        expect(status.total.excludedContributions, hasLength(1));
      }
    }
  });

  test(
    'conflicted printed dose stays excluded and visible beside a known dose',
    () {
      const aggregator = StackNutrientAggregator();
      final result = aggregator.aggregate([
        const StackItemNutrients(
          stackEntryId: 'conflict',
          productName: 'Printed conflict',
          ingredients: [
            {
              'ingredient': 'Molybdenum',
              'canonical_id': 'molybdenum',
              'quantity': 75,
              'unit': 'mg',
              'dose_data_quality': {'status': 'unresolved_unit'},
              'skip_ul_check': true,
              'skip_ul_reason': 'label_unit_conflict',
              'ul_assessment_status': 'indeterminate',
            },
          ],
        ),
        const StackItemNutrients(
          stackEntryId: 'known',
          productName: 'Known dose',
          ingredients: [
            {
              'ingredient': 'Molybdenum',
              'canonical_id': 'molybdenum',
              'quantity': 45,
              'unit': 'mcg',
              'safety_exposure': {'per_day': 45, 'unit': 'mcg'},
            },
          ],
        ),
      ]);
      final total = result['molybdenum']!;
      expect(total.hasUnresolvedUlContribution, isTrue);
      final statuses =
          const StackUlChecker(
            rdaData: {
              'nutrient_recommendations': [
                {
                  'id': 'molybdenum',
                  'standard_name': 'Molybdenum',
                  'unit': 'mcg',
                  'highest_ul': 2000,
                  'data': [
                    {
                      'group': 'Male',
                      'age_range': '19-30',
                      'rda_ai': 45,
                      'ul': 2000,
                    },
                  ],
                },
              ],
            },
          ).check(
            result,
            ageBracket: '19-30',
            sex: 'Male',
            pipelineVerdicts: {
              'molybdenum': const PipelineUlVerdict(overUl: false, pctUl: 2.25),
            },
          );
      expect(statuses.single.ulAssessmentIndeterminate, isTrue);
      expect(total.totalAmount, 45);
      expect(total.hasUnitConflict, isTrue);
      expect(total.excludedContributions, hasLength(1));
      expect(
        total.excludedContributions.single.reason,
        NutrientExclusionReason.unitConflict,
      );
      expect(total.excludedContributions.single.contribution.amount, 75);
    },
  );
  test(
    'conflict-only dose retains uncertainty without any numeric exposure',
    () {
      final totals = const StackNutrientAggregator().aggregate([
        const StackItemNutrients(
          stackEntryId: 'conflict',
          productName: 'Printed conflict',
          ingredients: [
            {
              'ingredient': 'Molybdenum',
              'canonical_id': 'molybdenum',
              'quantity': 75,
              'unit': 'mg',
              'dose_data_quality': {'status': 'unresolved_unit'},
            },
          ],
        ),
      ]);
      final status = const StackUlChecker(
        rdaData: {
          'nutrient_recommendations': [
            {
              'id': 'molybdenum',
              'standard_name': 'Molybdenum',
              'unit': 'mcg',
              'highest_ul': 2000,
              'data': [
                {
                  'group': 'Male',
                  'age_range': '19-30',
                  'rda_ai': 45,
                  'ul': 2000,
                },
              ],
            },
          ],
        },
      ).check(totals, ageBracket: '19-30', sex: 'Male').single;
      expect(status.ulAssessmentIndeterminate, isTrue);
      expect(status.pctOfUl, isNull);
      expect(status.pctOfRda, isNull);
      expect(status.total.contributions, isEmpty);
    },
  );
  test('pipeline safety exposure alone establishes the UL contract', () {
    final stack = List.generate(
      2,
      (i) => StackItemNutrients(
        stackEntryId: 'e$i',
        productName: 'Vitamin E',
        ingredients: [
          {
            'name': 'Vitamin E',
            'canonical_id': 'vitamin_e',
            'per_day_min': 337.5,
            'per_day_max': 337.5,
            'converted_unit': 'mg',
            'safety_exposure': {'per_day': 675.0, 'unit': 'mg'},
          },
        ],
      ),
    );
    final total = const StackNutrientAggregator().aggregate(stack);
    final statuses = const StackUlChecker(
      rdaData: {
        'nutrient_recommendations': [
          {
            'id': 'vitamin_e',
            'standard_name': 'Vitamin E',
            'unit': 'mg',
            'highest_ul': 1000,
            'data': [
              {'group': 'Male', 'age_range': '19-30', 'rda_ai': 15, 'ul': 1000},
            ],
          },
        ],
      },
    ).check(total, ageBracket: '19-30', sex: 'Male');
    expect(statuses.single.tier, NutrientTier.exceedsUl);
    expect(statuses.single.pctOfUl, 135);
    expect(statuses.single.pctOfRda, 4500);
  });

  test('synthetic vitamin E UL mass stays separate from activity intake', () {
    final stack = List.generate(
      2,
      (i) => StackItemNutrients(
        stackEntryId: 'e$i',
        productName: 'Vitamin E',
        ingredients: [
          {
            'name': 'Vitamin E',
            'canonical_id': 'vitamin_e',
            'per_day_min': 337.5,
            'per_day_max': 337.5,
            'converted_unit': 'mg',
            'ul_gate_eligible': true,
            'safety_exposure': {'per_day': 675.0, 'unit': 'mg'},
          },
        ],
      ),
    );
    final total = const StackNutrientAggregator().aggregate(
      stack,
    )['vitamin_e']!;
    expect(total.totalAmount, 675);
    expect(total.minimumTotalAmount, 675);
    expect(total.ulComparableTotalAmount, 1350);
  });

  const aggregator = StackNutrientAggregator();

  group('StackNutrientAggregator — ul_gate_eligible exclusion', () {
    test('Magtein-alone (ul_gate_eligible:false, no elemental sibling) is '
        'excluded from the sum, not counted at compound mass', () {
      final stack = [
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Magtein',
          ingredients: [
            {
              'canonical_id': 'magnesium',
              'name': 'Magnesium L-Threonate',
              'quantity': 2000,
              'unit': 'mg',
              'ul_gate_eligible': false,
              'ul_gate_ineligible_reason': 'compound_mass_not_elemental',
            },
          ],
        ),
      ];

      final total = aggregator.aggregate(stack)['magnesium']!;

      // The compound mass must NOT sum into the elemental-comparable total.
      expect(total.totalAmount, 0);
      expect(total.contributions, isEmpty);
      // Excluded, but still surfaced so the UI can trace the product.
      expect(total.excludedContributions, hasLength(1));
      expect(
        total.excludedContributions.single.reason,
        NutrientExclusionReason.compoundFormDuplicate,
      );
      expect(total.excludedContributions.single.contribution.amount, 2000);
      // It is NOT a unit conflict — must not raise that UI flag.
      expect(total.hasUnitConflict, isFalse);
    });

    test('ul_gate_eligible:true rows are summed normally (contract is opt-out '
        'only, dual-read safe)', () {
      final stack = [
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Chelated Mag',
          ingredients: [
            {
              'canonical_id': 'magnesium',
              'name': 'Magnesium',
              'quantity': 200,
              'unit': 'mg',
              'ul_gate_eligible': true,
            },
          ],
        ),
      ];

      final total = aggregator.aggregate(stack)['magnesium']!;
      expect(total.totalAmount, 200);
      expect(total.contributions, hasLength(1));
      expect(total.excludedContributions, isEmpty);
    });

    test('absent ul_gate_eligible field leaves legacy behavior unchanged', () {
      // Catalogs built before the field existed must still sum.
      final stack = [
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Legacy Mag',
          ingredients: [
            {
              'canonical_id': 'magnesium',
              'name': 'Magnesium',
              'quantity': 200,
              'unit': 'mg',
            },
          ],
        ),
      ];
      expect(aggregator.aggregate(stack)['magnesium']!.totalAmount, 200);
    });

    test('an eligible sibling still sums even when a co-listed compound row '
        'is gated out', () {
      // Elemental 60 mg row (eligible) + compound 2000 mg row (gated out):
      // only the elemental row counts.
      final stack = [
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Mixed Mag',
          ingredients: [
            {
              'canonical_id': 'magnesium',
              'name': 'Magnesium',
              'quantity': 60,
              'unit': 'mg',
            },
            {
              'canonical_id': 'magnesium',
              'name': 'Magnesium L-Threonate',
              'quantity': 2000,
              'unit': 'mg',
              'ul_gate_eligible': false,
              'ul_gate_ineligible_reason': 'compound_mass_not_elemental',
            },
          ],
        ),
      ];
      final total = aggregator.aggregate(stack)['magnesium']!;
      expect(total.totalAmount, 60);
      expect(total.contributions, hasLength(1));
      expect(total.excludedContributions, hasLength(1));
    });

    test('a non-compound row that lacks a UL verdict still contributes to '
        'the intake display', () {
      final stack = [
        const StackItemNutrients(
          stackEntryId: 's1',
          productName: 'Form-aware Vitamin A',
          ingredients: [
            {
              'canonical_id': 'vitamin_a',
              'name': 'Vitamin A',
              'quantity': 25000,
              'unit': 'IU',
              'ul_gate_eligible': false,
              'ul_gate_ineligible_reason':
                  'form_specific_conversion_unavailable',
            },
          ],
        ),
      ];

      final total = aggregator.aggregate(stack)['vitamin_a']!;
      expect(total.totalAmount, 25000);
      expect(total.unit, 'iu');
      expect(total.contributions, hasLength(1));
      expect(total.excludedContributions, isEmpty);
      expect(total.hasUnitConflict, isFalse);
    });
  });
}
