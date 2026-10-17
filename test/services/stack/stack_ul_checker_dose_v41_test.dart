// Dose V4.1 §4.1B (pipeline docs/plans/DOSE_V41_PLAN.md): the personal upper-
// limit checker compares one verified exposure against one applicable
// reference.
//
// 1. Exactly 100% of a limit is not an exceedance (pipeline §2.4).
// 2. Without a matched profile it screens against the lowest established limit
//    across ordinary adult groups (pipeline §2.5), never a child's or a
//    pregnancy row, and says the limit is not personal.
// 3. Percentage, tier and warning come from the same reference.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_ul_checker.dart';

void main() {
  const checker = StackUlChecker(rdaData: _rda);

  test('exactly 100% of the limit is not an exceedance', () {
    final status = checker
        .check(
          {'magnesium': _total('magnesium', 350)},
          ageBracket: '19-30',
          sex: 'Male',
        )
        .single;
    expect(status.pctOfUl, 100.0);
    expect(status.tier, NutrientTier.approachingUl);
    expect(status.shouldWarn, isTrue); // approaching still informs
  });

  test('just above 100% is an exceedance', () {
    final status = checker
        .check(
          {'magnesium': _total('magnesium', 351)},
          ageBracket: '19-30',
          sex: 'Male',
        )
        .single;
    expect(status.tier, NutrientTier.exceedsUl);
  });

  test(
    'anonymous screen uses the lowest ordinary-adult limit, not a child row',
    () {
      final status = checker.check({'calcium': _total('calcium', 2100)}).single;
      // Adults 51+ have 2,000 mg; the 14-18 row (3,000) and pregnancy rows are
      // other populations. 2,100 mg exceeds the general adult screen.
      expect(status.ul, 2000.0);
      expect(status.tier, NutrientTier.exceedsUl);
      expect(status.ulIsFallback, isTrue);
    },
  );

  test('anonymous screen does not take the adolescent zinc limit', () {
    final status = checker.check({'zinc': _total('zinc', 36)}).single;
    expect(status.ul, 40.0);
    expect(status.tier, NutrientTier.approachingUl);
  });

  test('a pregnancy profile without an age uses the adult pregnancy rows', () {
    final status = checker.check({
      'calcium': _total('calcium', 2100),
    }, sex: 'Pregnancy').single;
    expect(status.ul, 2500.0);
    expect(status.tier, NutrientTier.approachingUl);
    expect(status.ulIsFallback, isTrue);
  });

  test('the pipeline exposure is re-expressed against the person\'s limit', () {
    // Catalog screen: 2,100 mg at maximum labeled use is 105% of the general
    // adult 2,000 mg. This 19-30 profile's limit is 2,500 mg: 84%.
    final status = checker
        .check(
          {'calcium': _total('calcium', 900)},
          ageBracket: '19-30',
          sex: 'Female',
          pipelineVerdicts: const {
            'calcium': PipelineUlVerdict(overUl: true, pctUl: 105, ul: 2000),
          },
        )
        .single;
    expect(status.ul, 2500.0);
    expect(status.pctOfUl, closeTo(84.0, 0.01));
    expect(status.tier, NutrientTier.approachingUl);
  });

  test(
    'a catalog percentage is never paired with a different personal limit',
    () {
      final status = checker
          .check(
            {'calcium': _total('calcium', 900)},
            ageBracket: '19-30',
            sex: 'Female',
            pipelineVerdicts: const {
              'calcium': PipelineUlVerdict(overUl: true, pctUl: 120),
            },
          )
          .single;
      expect(status.tier, NutrientTier.exceedsUl);
      expect(status.pctOfUl, 120.0);
      expect(
        status.ul,
        isNull,
        reason: 'the 120% is against the catalog limit, not 2,500 mg',
      );
    },
  );

  test(
    'a percentage-only verdict exceeds above 100%, matching the pipeline',
    () {
      expect(const PipelineUlVerdict(pctUl: 120).exceedsUl, isTrue);
      expect(const PipelineUlVerdict(pctUl: 100).exceedsUl, isFalse);
    },
  );
}

NutrientTotal _total(String id, double amount) => NutrientTotal(
  canonicalId: id,
  displayName: id,
  totalAmount: amount,
  unit: 'mg',
  contributions: const [],
);

const _rda = {
  'nutrient_recommendations': [
    {
      'id': 'magnesium',
      'standard_name': 'Magnesium',
      'unit': 'mg',
      'data': [
        {'group': 'Male', 'age_range': '19-30', 'rda_ai': 400, 'ul': 350},
        {'group': 'Female', 'age_range': '19-30', 'rda_ai': 310, 'ul': 350},
      ],
    },
    {
      'id': 'calcium',
      'standard_name': 'Calcium',
      'unit': 'mg',
      'data': [
        {'group': 'Male', 'age_range': '14-18', 'rda_ai': 1300, 'ul': 3000},
        {'group': 'Male', 'age_range': '19-30', 'rda_ai': 1000, 'ul': 2500},
        {'group': 'Female', 'age_range': '19-30', 'rda_ai': 1000, 'ul': 2500},
        {'group': 'Female', 'age_range': '51-70', 'rda_ai': 1200, 'ul': 2000},
        {'group': 'Male', 'age_range': '71+', 'rda_ai': 1200, 'ul': 2000},
        {
          'group': 'Pregnancy',
          'age_range': '14-18',
          'rda_ai': 1300,
          'ul': 3000,
        },
        {
          'group': 'Pregnancy',
          'age_range': '19-30',
          'rda_ai': 1000,
          'ul': 2500,
        },
        {
          'group': 'Pregnancy',
          'age_range': '31-50',
          'rda_ai': 1000,
          'ul': 2500,
        },
      ],
    },
    {
      'id': 'zinc',
      'standard_name': 'Zinc',
      'unit': 'mg',
      'data': [
        {'group': 'Female', 'age_range': '14-18', 'rda_ai': 9, 'ul': 34},
        {'group': 'Male', 'age_range': '19-30', 'rda_ai': 11, 'ul': 40},
        {'group': 'Female', 'age_range': '19-30', 'rda_ai': 8, 'ul': 40},
      ],
    },
  ],
};
