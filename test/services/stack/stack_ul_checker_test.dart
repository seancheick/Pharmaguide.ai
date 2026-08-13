// Tests for [StackUlChecker].
//
// Uses a hand-built minimal RDA fixture that mirrors the real
// `rda_optimal_uls.json` shape (id, standard_name, highest_ul,
// data[{group, age_range, rda_ai, ul}]). Keeping the fixture
// inline makes each test easy to read in isolation and avoids the
// root-bundle asset loader which needs a widget test context.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_ul_checker.dart';

void main() {
  // Minimal fixture matching the real reference data contract.
  final rdaFixture = {
    '_metadata': {'schema_version': '5.0.0'},
    'consumer_ul_warnings': {
      'vitamin_d3': {'message': 'Too much can cause kidney problems.'},
      'zinc': {
        'message':
            'Long-term excessive zinc can reduce copper absorption and lead to copper deficiency.',
      },
      'magnesium': {
        'message': 'Too much supplemental magnesium can cause diarrhea.',
      },
      'iron': {'message': 'High doses can cause stomach problems.'},
      'vitamin_a': {
        'message': 'Too much preformed vitamin A can harm the liver.',
      },
      'folate': {
        'message': 'Too much folic acid can hide a vitamin B12 deficiency.',
      },
      'niacin': {'message': 'Too much supplemental niacin can cause flushing.'},
    },
    'nutrient_recommendations': [
      {
        'id': 'vitamin_d3',
        'standard_name': 'Vitamin D3',
        'unit': 'IU',
        'highest_ul': 4000,
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 600, 'ul': 4000},
          {'group': 'Female', 'age_range': '19-30', 'rda_ai': 600, 'ul': 4000},
          {'group': 'Male', 'age_range': '31-50', 'rda_ai': 600, 'ul': 4000},
        ],
      },
      {
        'id': 'zinc',
        'standard_name': 'Zinc',
        'unit': 'mg',
        'highest_ul': 40,
        'data': [
          {'group': 'Female', 'age_range': '14-18', 'rda_ai': 9, 'ul': 34},
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 11, 'ul': 40},
          {'group': 'Female', 'age_range': '19-30', 'rda_ai': 8, 'ul': 40},
        ],
      },
      {
        'id': 'magnesium',
        'standard_name': 'Magnesium',
        'unit': 'mg',
        'highest_ul': 350,
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 400, 'ul': 350},
          {'group': 'Female', 'age_range': '19-30', 'rda_ai': 310, 'ul': 350},
        ],
      },
      {
        'id': 'iron',
        'standard_name': 'Iron',
        'unit': 'mg',
        'highest_ul': 45,
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 8, 'ul': 45},
          {'group': 'Female', 'age_range': '19-30', 'rda_ai': 18, 'ul': 45},
        ],
      },
      {
        'id': 'thiamin',
        'standard_name': 'Thiamin',
        'unit': 'mg',
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 1.2},
        ],
      },
      {
        // Entry with no UL at all — e.g. some B vitamins.
        'id': 'vitamin_b12',
        'standard_name': 'Vitamin B12',
        'unit': 'mcg',
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 2.4},
          {'group': 'Female', 'age_range': '19-30', 'rda_ai': 2.4},
        ],
      },
      {
        'id': 'pantothenic_acid',
        'standard_name': 'Pantothenic Acid',
        'unit': 'mg',
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 5},
        ],
      },
      {
        'id': 'biotin',
        'standard_name': 'Biotin',
        'unit': 'mcg',
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 30},
        ],
      },
      {
        'id': 'vitamin_a',
        'standard_name': 'Vitamin A',
        'unit': 'mcg RAE',
        'highest_ul': 3000,
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 900, 'ul': 3000},
          {'group': 'Female', 'age_range': '19-30', 'rda_ai': 700, 'ul': 3000},
        ],
      },
      {
        'id': 'vitamin_k',
        'standard_name': 'Vitamin K',
        'unit': 'mcg',
        'nutrient_class': 'floor',
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 120},
          {'group': 'Female', 'age_range': '19-30', 'rda_ai': 90},
        ],
      },
      {
        'id': 'folate',
        'standard_name': 'Folate',
        'unit': 'mcg DFE',
        'highest_ul': 1667,
        'data': [
          {'group': 'Female', 'age_range': '19-30', 'rda_ai': 400, 'ul': 1667},
          {
            'group': 'Pregnancy',
            'age_range': '19-30',
            'rda_ai': 600,
            'ul': 1667,
          },
        ],
      },
      {
        'id': 'niacin',
        'standard_name': 'Niacin',
        'unit': 'mg NE',
        'highest_ul': 35,
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 16, 'ul': 35},
        ],
      },
      {
        'id': 'alpha_linolenic_acid',
        'standard_name': 'Alpha-Linolenic Acid',
        'unit': 'g',
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 1.6},
        ],
      },
      {
        // Floor nutrient whose only `highest_ul` is a soft toxicity-study
        // estimate (vanadium has no official UL). nutrient_class='floor' must
        // suppress it so the tier never escalates to a UL warning.
        'id': 'vanadium',
        'standard_name': 'Vanadium',
        'unit': 'mcg',
        'nutrient_class': 'floor',
        'highest_ul': 1800,
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 50},
        ],
      },
    ],
  };

  final checker = StackUlChecker(rdaData: rdaFixture);

  test('replays the O.N.E. Multivitamin plus Calcium K/D benchmark rows', () {
    const aggregator = StackNutrientAggregator();
    final totals = aggregator.aggregate([
      const StackItemNutrients(
        stackEntryId: 'one',
        productName: 'O.N.E. Multivitamin',
        ingredients: [
          {
            'canonical_id': 'vitamin_a',
            'standard_name': 'Vitamin A',
            'per_day_min': 1125,
            'per_day_max': 1125,
            'converted_unit': 'mcg',
            'skip_ul_check': true,
            'skip_ul_reason': 'unknown_vitamin_form',
          },
        ],
      ),
      const StackItemNutrients(
        stackEntryId: 'cal-kd',
        productName: 'Calcium K/D',
        ingredients: [
          {
            'canonical_id': 'vitamin_k1',
            'nutrient_group_id': 'vitamin_k',
            'nutrient_group_name': 'Vitamin K',
            'ingredient': 'Vitamin K1',
            'per_day_min': 100,
            'per_day_max': 300,
            'converted_unit': 'mcg',
          },
          {
            'canonical_id': 'vitamin_k2',
            'nutrient_group_id': 'vitamin_k',
            'nutrient_group_name': 'Vitamin K',
            'ingredient': 'Vitamin K2',
            'per_day_min': 30,
            'per_day_max': 90,
            'converted_unit': 'mcg',
          },
        ],
      ),
    ]);

    final statuses = {
      for (final status in checker.check(
        totals,
        ageBracket: '19-30',
        sex: 'Male',
      ))
        status.total.canonicalId: status,
    };

    expect(statuses['vitamin_a']!.pctOfRda, closeTo(125, 0.1));
    expect(statuses['vitamin_a']!.pctOfUl, isNull);
    expect(statuses['vitamin_a']!.ulAssessmentIndeterminate, isTrue);
    expect(statuses['vitamin_k']!.total.displayName, 'Vitamin K');
    expect(statuses['vitamin_k']!.total.minimumTotalAmount, 130);
    expect(statuses['vitamin_k']!.total.totalAmount, 390);
    expect(statuses['vitamin_k']!.pctOfRda, closeTo(108.3, 0.1));
    expect(statuses['vitamin_k']!.maximumPctOfRda, closeTo(325, 0.1));
  });

  test('counts known non-folic folate without applying the folic-acid UL', () {
    const aggregator = StackNutrientAggregator();
    final totals = aggregator.aggregate([
      const StackItemNutrients(
        stackEntryId: 'methylfolate',
        productName: 'Methylfolate supplement',
        ingredients: [
          {
            'canonical_id': 'folate',
            'name': 'Folate',
            'per_day_min': 5000,
            'per_day_max': 5000,
            'converted_unit': 'mcg DFE',
            'skip_ul_check': true,
            'skip_ul_reason': 'non_folic_acid_folate_ul_basis',
          },
        ],
      ),
    ]);

    final total = totals['folate']!;
    expect(total.totalAmount, 5000, reason: 'disclosed intake stays counted');

    final status = checker
        .check(totals, ageBracket: '19-30', sex: 'Female')
        .single;
    expect(status.pctOfRda, closeTo(1250, 0.1));
    expect(status.pctOfUl, isNull);
    expect(status.shouldWarn, isFalse);
    expect(
      status.ulAssessmentIndeterminate,
      isFalse,
      reason: 'a known outside-scope form is not missing label data',
    );
  });

  test(
    'counts unknown-form vitamin E without guessing its synthetic UL share',
    () {
      const localChecker = StackUlChecker(
        rdaData: {
          'consumer_ul_warnings': {
            'vitamin_e': {
              'message': 'High supplemental doses can increase bleeding.',
            },
          },
          'nutrient_recommendations': [
            {
              'id': 'vitamin_e',
              'standard_name': 'Vitamin E',
              'unit': 'mg alpha-tocopherol',
              'data': [
                {
                  'group': 'Female',
                  'age_range': '19-30',
                  'rda_ai': 15,
                  'ul': 1000,
                },
              ],
            },
          ],
        },
      );
      const aggregator = StackNutrientAggregator();
      final totals = aggregator.aggregate([
        const StackItemNutrients(
          stackEntryId: 'e',
          productName: 'Mixed tocopherols',
          ingredients: [
            {
              'canonical_id': 'vitamin_e',
              'name': 'Vitamin E',
              'per_day_min': 1005,
              'per_day_max': 1005,
              'converted_unit': 'mg alpha-tocopherol',
              'skip_ul_check': true,
              'skip_ul_reason': 'unknown_vitamin_form',
            },
          ],
        ),
      ]);

      final status = localChecker
          .check(totals, ageBracket: '19-30', sex: 'Female')
          .single;
      expect(status.total.totalAmount, 1005);
      expect(status.pctOfUl, isNull);
      expect(status.shouldWarn, isFalse);
      expect(status.ulAssessmentIndeterminate, isTrue);
    },
  );

  test('still aggregates UL-eligible folic-acid exposure across products', () {
    const aggregator = StackNutrientAggregator();
    final totals = aggregator.aggregate([
      const StackItemNutrients(
        stackEntryId: 'one',
        productName: 'Folic acid one',
        ingredients: [
          {
            'canonical_id': 'folate',
            'name': 'Folic Acid',
            'per_day_min': 900,
            'per_day_max': 900,
            'converted_unit': 'mcg DFE',
            'ul_gate_eligible': true,
          },
        ],
      ),
      const StackItemNutrients(
        stackEntryId: 'two',
        productName: 'Folic acid two',
        ingredients: [
          {
            'canonical_id': 'folate',
            'name': 'Folic Acid',
            'per_day_min': 900,
            'per_day_max': 900,
            'converted_unit': 'mcg DFE',
            'ul_gate_eligible': true,
          },
        ],
      ),
    ]);

    final status = checker
        .check(totals, ageBracket: '19-30', sex: 'Female')
        .single;
    expect(status.total.totalAmount, 1800);
    expect(status.pctOfUl, closeTo(108, 0.1));
    expect(status.tier, NutrientTier.exceedsUl);
  });

  test('folate label total and UL-scoped child are not double counted', () {
    const aggregator = StackNutrientAggregator();
    final totals = aggregator.aggregate([
      const StackItemNutrients(
        stackEntryId: 'multi',
        productName: 'One Daily Multivitamin',
        ingredients: [
          {
            'canonical_id': 'folate',
            'name': 'Folate',
            'per_day_min': 1360,
            'per_day_max': 1360,
            'converted_unit': 'mcg DFE',
            'skip_ul_check': true,
            'skip_ul_reason': 'unknown_folate_form_lineage',
            'source_label_key': 'folate-total',
          },
          {
            'canonical_id': 'folate',
            'name': 'Folic Acid',
            'per_day_min': 680,
            'per_day_max': 680,
            'converted_unit': 'mcg DFE',
            'dose_role': 'ul_scoped_component',
            'parent_label_key': 'folate-total',
            'ul_gate_eligible': true,
          },
        ],
      ),
    ]);

    final status = checker
        .check(totals, ageBracket: '19-30', sex: 'Female')
        .single;
    expect(
      status.total.totalAmount,
      1360,
      reason: 'the label total appears once',
    );
    expect(status.pctOfUl, closeTo(40.8, 0.1));
    expect(status.tier, NutrientTier.aboveTypical);
    expect(status.ulAssessmentIndeterminate, isTrue);
  });

  group('StackUlChecker — tier classification', () {
    test('noRda tier when nutrient is not in reference data', () {
      final totals = _totals([_total('unknownium', 'Unknownium', 500, 'mg')]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results, hasLength(1));
      expect(results.first.tier, NutrientTier.noRda);
      expect(results.first.rda, isNull);
      expect(results.first.ul, isNull);
    });

    test('underFifty tier when below 50% RDA', () {
      // Male 19-30 D3 RDA = 600 IU; 200 IU = 33%
      final totals = _totals([_total('vitamin_d3', 'Vitamin D3', 200, 'IU')]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.tier, NutrientTier.underFifty);
      expect(results.first.pctOfRda, closeTo(33.3, 0.1));
    });

    test('adequate tier in the 50-100% RDA range', () {
      // 400 IU of 600 = 66.6%
      final totals = _totals([_total('vitamin_d3', 'Vitamin D3', 400, 'IU')]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.tier, NutrientTier.adequate);
      expect(results.first.pctOfRda, closeTo(66.6, 0.1));
    });

    test('abundant tier in the 100-200% RDA range', () {
      // 900 IU of 600 = 150%
      final totals = _totals([_total('vitamin_d3', 'Vitamin D3', 900, 'IU')]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.tier, NutrientTier.abundant);
      expect(results.first.pctOfRda, closeTo(150.0, 0.1));
    });

    test('aboveTypical tier when above 200% RDA but below 80% UL', () {
      // 2000 IU D3: RDA=600, UL=4000. %RDA=333, %UL=50.
      final totals = _totals([_total('vitamin_d3', 'Vitamin D3', 2000, 'IU')]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.tier, NutrientTier.aboveTypical);
      expect(results.first.pctOfRda, closeTo(333.3, 0.1));
      expect(results.first.pctOfUl, closeTo(50.0, 0.1));
    });

    test('approachingUl tier at 80-100% UL', () {
      // 3500 IU D3, UL=4000, 87.5% UL
      final totals = _totals([_total('vitamin_d3', 'Vitamin D3', 3500, 'IU')]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.tier, NutrientTier.approachingUl);
      expect(results.first.pctOfUl, closeTo(87.5, 0.1));
      expect(results.first.warning, isNotNull);
      expect(results.first.shouldWarn, isTrue);
    });

    test('exceedsUl tier above 100% UL', () {
      // The zinc stacking scenario from the spec: 52 mg, UL=40, 130% UL
      final totals = _totals([_total('zinc', 'Zinc', 52, 'mg')]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.tier, NutrientTier.exceedsUl);
      expect(results.first.pctOfUl, closeTo(130.0, 0.1));
      expect(results.first.warning, contains('copper deficiency'));
      expect(results.first.shouldWarn, isTrue);
    });

    test('UL precedence: exceedsUl wins over abundant RDA', () {
      // Magnesium male: RDA=400, UL=350. Total=500 → 125% RDA but 143% UL
      // Result must be exceedsUl, not abundant.
      final totals = _totals([_total('magnesium', 'Magnesium', 500, 'mg')]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.tier, NutrientTier.exceedsUl);
    });
  });

  group('StackUlChecker — demographic lookup', () {
    test(
      'uses minimum exposure for target and maximum exposure for safety',
      () {
        const total = NutrientTotal(
          canonicalId: 'vitamin_k',
          displayName: 'Vitamin K',
          minimumTotalAmount: 130,
          totalAmount: 390,
          unit: 'mcg',
          contributions: [],
        );

        final result = checker
            .check({'vitamin_k': total}, ageBracket: '19-30', sex: 'Male')
            .single;

        expect(result.pctOfRda, closeTo(108.3, 0.1));
        expect(result.maximumPctOfRda, closeTo(325.0, 0.1));
        expect(result.ul, isNull);
        expect(result.pctOfUl, isNull);
        expect(result.tier, NutrientTier.aboveAdequateNoUl);
      },
    );

    test('Vitamin A mcg supports target but not a mixed-form UL guess', () {
      const total = NutrientTotal(
        canonicalId: 'vitamin_a',
        displayName: 'Vitamin A',
        totalAmount: 1125,
        unit: 'mcg',
        contributions: [],
      );

      final result = checker
          .check({'vitamin_a': total}, ageBracket: '19-30', sex: 'Male')
          .single;

      expect(result.pctOfRda, closeTo(125.0, 0.1));
      expect(result.ul, 3000);
      expect(result.pctOfUl, isNull);
      expect(result.ulAssessmentIndeterminate, isTrue);
      expect(result.tier, NutrientTier.abundant);
    });

    test('male RDA differs from female RDA for iron', () {
      final male = checker.check(
        _totals([_total('iron', 'Iron', 18, 'mg')]),
        ageBracket: '19-30',
        sex: 'Male',
      );
      final female = checker.check(
        _totals([_total('iron', 'Iron', 18, 'mg')]),
        ageBracket: '19-30',
        sex: 'Female',
      );
      // Male RDA=8 so 18mg is 225% (aboveTypical)
      // Female RDA=18 so 18mg is exactly 100% (abundant)
      expect(male.first.tier, NutrientTier.aboveTypical);
      expect(female.first.tier, NutrientTier.abundant);
    });

    test('falls back to any-sex match when exact sex not found', () {
      // No "Other" group in fixture — should fall back to first matching age.
      final results = checker.check(
        _totals([_total('zinc', 'Zinc', 15, 'mg')]),
        ageBracket: '19-30',
        sex: 'Other',
      );
      expect(results.first.rda, isNotNull);
    });

    test(
      'anonymous user uses the lowest established ceiling, not highest_ul',
      () {
        final totals = _totals([_total('zinc', 'Zinc', 45, 'mg')]);
        final results = checker.check(totals);
        // Anonymous users now receive a baseline RDA (Female 19-30) so
        // %RDA displays without a profile. UL check still dominates —
        // 45mg > 40mg UL takes precedence over any RDA-based tiering.
        expect(results.first.rda, 8.0);
        expect(results.first.rdaIsBaseline, isTrue);
        expect(results.first.ul, 34);
        expect(results.first.tier, NutrientTier.exceedsUl);
        expect(results.first.warning, contains('copper deficiency'));
      },
    );

    test('anonymous adequate amount uses baseline RDA without UL warning', () {
      final totals = _totals([_total('zinc', 'Zinc', 10, 'mg')]);
      final results = checker.check(totals);
      // 10mg vs baseline RDA 8mg = 125% → abundant tier. No UL warning
      // because 10mg < 80% of UL (40). `rdaIsBaseline` flags the UI to
      // show a subtle hint that this is a generic adult reference.
      expect(results.first.rda, 8.0);
      expect(results.first.rdaIsBaseline, isTrue);
      expect(results.first.tier, NutrientTier.abundant);
      expect(results.first.shouldWarn, isFalse);
    });

    test('profile-matched RDA is not flagged as baseline', () {
      final totals = _totals([_total('zinc', 'Zinc', 10, 'mg')]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      // Profile match should set rdaIsBaseline = false so the UI
      // renders the value without the "*" hint.
      expect(results.first.rda, isNotNull);
      expect(results.first.rdaIsBaseline, isFalse);
    });

    test('pregnancy group uses pregnancy RDA instead of female RDA', () {
      final results = checker.check(
        _totals([_total('vitamin_b9_folate', 'Folate', 600, 'mcg DFE')]),
        ageBracket: '19-30',
        sex: 'Pregnancy',
      );
      expect(results.first.rda, 600);
      expect(results.first.pctOfRda, closeTo(100, 0.1));
    });

    test('anonymous UL fallback is marked as fallback provenance', () {
      final results = checker.check(
        _totals([_total('zinc', 'Zinc', 10, 'mg')]),
      );
      expect(results.first.ul, 34);
      expect(results.first.ulIsFallback, isTrue);
    });

    test('floor nutrient_class suppresses a soft highest_ul ceiling', () {
      // Vanadium's only `highest_ul` (1800) is a toxicity-study estimate, not
      // an official UL. nutrient_class='floor' must keep it off the UL ladder
      // even when the amount is far above that number — no UL, no warning.
      final totals = _totals([_total('vanadium', 'Vanadium', 2000, 'mcg')]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.ul, isNull);
      expect(results.first.pctOfUl, isNull);
      expect(results.first.tier, NutrientTier.aboveAdequateNoUl);
      expect(results.first.shouldWarn, isFalse);
    });
  });

  group('StackUlChecker — fuzzy name matching', () {
    test('exact standard_name match when canonical id misses', () {
      final totals = _totals([
        const NutrientTotal(
          canonicalId: 'not_a_known_id',
          displayName: 'Vitamin D3',
          totalAmount: 2000,
          unit: 'IU',
          contributions: [],
        ),
      ]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.rda, 600);
      expect(results.first.tier, NutrientTier.aboveTypical);
    });

    test('substring match works for longer ingredient names', () {
      final totals = _totals([
        const NutrientTotal(
          canonicalId: 'some_variant',
          displayName: 'Zinc picolinate',
          totalAmount: 15,
          unit: 'mg',
          contributions: [],
        ),
      ]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.rda, 11);
    });

    test(
      'pipeline B-vitamin canonical ids resolve through explicit aliases',
      () {
        final results = checker.check(
          _totals([
            _total('vitamin_b3_niacin', 'Vitamin B3 (Niacin)', 40, 'mg NE'),
          ]),
          ageBracket: '19-30',
          sex: 'Male',
        );
        expect(results.first.tier, NutrientTier.exceedsUl);
        expect(results.first.warning, contains('flushing'));
      },
    );

    test('pipeline parenthetical B1 standard name resolves to thiamin', () {
      final results = checker.check(
        _totals([
          _total('vitamin b1 (thiamine)', 'Vitamin B1 (Thiamine)', 1.2, 'mg'),
        ]),
        ageBracket: '19-30',
        sex: 'Male',
      );

      expect(results.first.rda, 1.2);
      expect(results.first.tier, NutrientTier.aboveAdequateNoUl);
    });

    test('pipeline B5/B7 parenthetical names resolve through aliases', () {
      final results = checker.check(
        _totals([
          _total(
            'vitamin b5 (pantothenic acid)',
            'Vitamin B5 (Pantothenic Acid)',
            5,
            'mg',
          ),
          _total('vitamin b7 (biotin)', 'Vitamin B7 (Biotin)', 30, 'mcg'),
        ]),
        ageBracket: '19-30',
        sex: 'Male',
      );

      expect(results.map((r) => r.rda), containsAll([5, 30]));
      expect(
        results.every((r) => r.tier == NutrientTier.aboveAdequateNoUl),
        isTrue,
      );
    });

    test('short malformed display names do not fuzzy-match nutrients', () {
      final results = checker.check(
        _totals([_total('unknown', 'K', 100, 'mg')]),
        ageBracket: '19-30',
        sex: 'Male',
      );
      expect(results.first.tier, NutrientTier.noRda);
    });

    test('EPA is not scored against alpha-linolenic acid RDA', () {
      final results = checker.check(
        _totals([_total('epa', 'EPA (Eicosapentaenoic Acid)', 1000, 'mg')]),
        ageBracket: '19-30',
        sex: 'Male',
      );
      expect(results.first.tier, NutrientTier.noRda);
      expect(results.first.rda, isNull);
    });
  });

  group('StackUlChecker — unit validation', () {
    test('refuses to compare actual unit against incompatible RDA unit', () {
      final results = checker.check(
        _totals([_total('zinc', 'Zinc', 40000, 'IU')]),
        ageBracket: '19-30',
        sex: 'Male',
      );
      expect(results.first.tier, NutrientTier.noRda);
      expect(results.first.pctOfUl, isNull);
      expect(results.first.warning, isNull);
    });

    test('converts simple metric mass units before RDA comparison', () {
      final results = checker.check(
        _totals([
          _total('alpha-linolenic acid', 'Alpha-Linolenic Acid', 1600, 'mg'),
        ]),
        ageBracket: '19-30',
        sex: 'Male',
      );

      expect(results.first.rda, 1.6);
      expect(results.first.pctOfRda, closeTo(100, 0.1));
      expect(results.first.tier, NutrientTier.aboveAdequateNoUl);
    });

    test('accepts gram(s) spelling from pipeline mass units', () {
      final results = checker.check(
        _totals([
          _total(
            'alpha-linolenic acid',
            'Alpha-Linolenic Acid',
            1.6,
            'gram(s)',
          ),
        ]),
        ageBracket: '19-30',
        sex: 'Male',
      );

      expect(results.first.pctOfRda, closeTo(100, 0.1));
      expect(results.first.tier, NutrientTier.aboveAdequateNoUl);
    });

    test('accepts expected-unit aliases for niacin equivalents', () {
      final results = checker.check(
        _totals([_total('niacin', 'Niacin', 35, 'mg')]),
        ageBracket: '19-30',
        sex: 'Male',
      );
      expect(results.first.tier, NutrientTier.exceedsUl);
      expect(results.first.pctOfUl, closeTo(100, 0.1));
    });
  });

  group('StackUlChecker — nutrients with no UL', () {
    test(
      'vitamin B12 (no UL) above target is benign, not an amber warning',
      () {
        final totals = _totals([
          _total('vitamin_b12', 'Vitamin B12', 5, 'mcg'),
        ]);
        final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
        // RDA=2.4, 5mcg = 208% RDA, NO UL → calm "above adequate", NOT the
        // amber aboveTypical/abundant tiers (those imply a ceiling to monitor).
        expect(results.first.tier, NutrientTier.aboveAdequateNoUl);
        expect(results.first.ul, isNull);
        expect(results.first.shouldWarn, isFalse);
      },
    );

    test('vitamin B12 at target level is above-adequate (no UL)', () {
      final totals = _totals([
        _total('vitamin_b12', 'Vitamin B12', 2.4, 'mcg'),
      ]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.tier, NutrientTier.aboveAdequateNoUl);
    });

    test('no-UL nutrient far above target never lands in a warning tier', () {
      // B12 at 24 mcg = 1000% of the 2.4 mcg target — common in supplements,
      // clinically benign (no ceiling exists). Must stay calm/green.
      final totals = _totals([_total('vitamin_b12', 'Vitamin B12', 24, 'mcg')]);
      final s = checker.check(totals, ageBracket: '19-30', sex: 'Male').first;
      expect(s.tier, NutrientTier.aboveAdequateNoUl);
      expect(s.tier, isNot(NutrientTier.aboveTypical));
      expect(s.tier, isNot(NutrientTier.abundant));
      expect(s.shouldWarn, isFalse);
    });

    test('a no-UL nutrient below target still reads adequate/underFifty', () {
      // Adequacy classification is unchanged below 100% — only the
      // above-target amber escalation is removed for no-UL nutrients.
      final totals = _totals([
        _total('vitamin_b12', 'Vitamin B12', 1.5, 'mcg'),
      ]);
      final s = checker.check(totals, ageBracket: '19-30', sex: 'Male').first;
      expect(s.tier, NutrientTier.adequate); // 1.5/2.4 = 62%
    });
  });

  group('StackUlChecker — warning strings', () {
    test('vitamin D excess uses calm, clinically precise shared copy', () {
      final results = checker.check(
        _totals([_total('vitamin_d3', 'Vitamin D3', 5000, 'IU')]),
        ageBracket: '19-30',
        sex: 'Male',
      );
      expect(
        results.first.warning,
        'Above the upper limit — Too much can cause kidney problems.',
      );
    });

    test(
      'zinc excess explains the chronic copper effect in plain language',
      () {
        final results = checker.check(
          _totals([_total('zinc', 'Zinc', 60, 'mg')]),
          ageBracket: '19-30',
          sex: 'Male',
        );
        final warning = results.first.warning;
        expect(warning, contains('copper deficiency'));
        expect(warning, contains('Long-term'));
        expect(warning, isNot(contains('copper alongside')));
      },
    );

    test('iron excess uses plain-language stomach-effect copy', () {
      final results = checker.check(
        _totals([_total('iron', 'Iron', 50, 'mg')]),
        ageBracket: '19-30',
        sex: 'Male',
      );
      expect(results.first.warning, contains('stomach problems'));
    });

    test('fuzzy nutrient lookup still selects the authored warning', () {
      // The total's id is deliberately off-schema. Once the reference entry
      // resolves by its display name, that entry's authored copy still owns
      // the message; the checker never invents a generic fallback.
      final totals = _totals([
        const NutrientTotal(
          canonicalId: 'not_specific',
          displayName: 'Vitamin D3',
          totalAmount: 5000,
          unit: 'IU',
          contributions: [],
        ),
      ]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.tier, NutrientTier.exceedsUl);
      expect(results.first.warning, contains('kidney problems'));
    });
  });

  group('StackUlChecker — empty and edge cases', () {
    test('empty aggregation returns empty list', () {
      expect(checker.check(<String, NutrientTotal>{}), isEmpty);
    });

    test('checker with empty rda data returns noRda for everything', () {
      const emptyChecker = StackUlChecker(
        rdaData: {'nutrient_recommendations': <dynamic>[]},
      );
      final results = emptyChecker.check(
        _totals([_total('zinc', 'Zinc', 15, 'mg')]),
      );
      expect(results.first.tier, NutrientTier.noRda);
    });

    test('checker with malformed rda data does not crash', () {
      const brokenChecker = StackUlChecker(
        rdaData: {
          'nutrient_recommendations': [
            'not a map',
            {'id': 'valid_but_no_data'},
            {'id': 'bad_data', 'data': 'not a list'},
          ],
        },
      );
      expect(
        () => brokenChecker.check(
          _totals([_total('zinc', 'Zinc', 15, 'mg')]),
          ageBracket: '19-30',
          sex: 'Male',
        ),
        returnsNormally,
      );
    });
  });
}

Map<String, NutrientTotal> _totals(List<NutrientTotal> list) => {
  for (final t in list) t.canonicalId: t,
};

NutrientTotal _total(
  String canonicalId,
  String displayName,
  double amount,
  String unit,
) => NutrientTotal(
  canonicalId: canonicalId,
  displayName: displayName,
  totalAmount: amount,
  unit: unit,
  contributions: const [],
);
