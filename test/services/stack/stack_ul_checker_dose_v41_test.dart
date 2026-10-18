// Dose V4.1 §4.1B (pipeline docs/plans/DOSE_V41_PLAN.md): the personal upper-
// limit checker compares one verified exposure against one applicable
// reference.
//
// 1. Exactly 100% of a limit is not an exceedance (pipeline §2.4).
// 2. Without demographic information it screens against the lowest established limit
//    across ordinary adult groups (pipeline §2.5), never a child's or a
//    pregnancy row, and says the limit is not personal.
// 3. Percentage, tier and warning come from the same reference.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_ul_checker.dart';

void main() {
  const checker = StackUlChecker(rdaData: _rda);

  group('source-owned form-scoped UL provenance', () {
    final scopedChecker = StackUlChecker(
      rdaData: {
        'consumer_ul_warnings': {
          'nickel': {'message': 'Pipeline-authored form-scoped warning.'},
        },
        'nutrient_recommendations': [
          {
            'id': 'nickel',
            'standard_name': 'Nickel',
            'unit': 'mg',
            'ul_applies_to_forms': ['nickel sulfate', 'nickel chloride'],
            'data': [
              {'group': 'Male', 'age_range': '19-30', 'ul': 1.0},
            ],
          },
          ..._rda['nutrient_recommendations'] as List,
        ],
      },
    );
    const aggregator = StackNutrientAggregator();

    test('legacy nickel intake cannot establish a soluble-salt exposure', () {
      final totals = aggregator.aggregate([_ulItem('legacy', 'nickel', 2)]);
      final status = scopedChecker
          .check(totals, ageBracket: '19-30', sex: 'Male')
          .single;
      expect(status.total.totalAmount, 2);
      expect(status.ulAssessmentIndeterminate, isTrue);
      expect(status.pctOfUl, isNull);
      expect(status.tier, isNot(NutrientTier.exceedsUl));
      expect(status.shouldWarn, isFalse);
    });

    test('an ordinary nutrient role alone is not form-scoped UL proof', () {
      final totals = aggregator.aggregate([
        const StackItemNutrients(
          stackEntryId: 'role-only',
          productName: 'Role only',
          ingredients: [
            {
              'canonical_id': 'nickel',
              'name': 'Nickel',
              'quantity': 2,
              'unit': 'mg',
              'dose_role': 'nutrient',
            },
          ],
        ),
      ]);
      final status = scopedChecker
          .check(totals, ageBracket: '19-30', sex: 'Male')
          .single;
      expect(status.total.hasUlExposureContract, isFalse);
      expect(status.ulAssessmentIndeterminate, isTrue);
      expect(status.pctOfUl, isNull);
      expect(status.shouldWarn, isFalse);
    });

    for (final amount in [1.0, 1.2]) {
      test('qualified nickel $amount mg uses the pipeline exposure', () {
        final totals = aggregator.aggregate([
          _ulItem('typed', 'nickel', amount, typed: true),
        ]);
        final status = scopedChecker
            .check(totals, ageBracket: '19-30', sex: 'Male')
            .single;
        expect(status.ulAssessmentIndeterminate, isFalse);
        expect(status.pctOfUl, closeTo(amount * 100, 0.0001));
        expect(
          status.tier,
          amount == 1 ? NutrientTier.approachingUl : NutrientTier.exceedsUl,
        );
      });
    }

    for (final typedAmount in [0.6, 1.2]) {
      test(
        'mixed scoped stack retains only the proven $typedAmount mg concern',
        () {
          final totals = aggregator.aggregate([
            _ulItem('typed', 'nickel', typedAmount, typed: true),
            _ulItem('legacy', 'nickel', 2),
          ]);
          final status = scopedChecker
              .check(totals, ageBracket: '19-30', sex: 'Male')
              .single;
          expect(status.total.totalAmount, closeTo(typedAmount + 2, 0.0001));
          expect(status.ulAssessmentIndeterminate, isTrue);
          expect(
            status.pctOfUl,
            isNull,
            reason: 'the full stack form scope is unknown',
          );
          expect(status.shouldWarn, typedAmount > 1);
          if (typedAmount > 1) {
            expect(status.tier, NutrientTier.exceedsUl);
            expect(status.warning, isNotNull);
          }
        },
      );
    }

    test(
      'an excluded legacy unit cannot complete the form-scoped stack percentage',
      () {
        final totals = aggregator.aggregate([
          _ulItem('typed', 'nickel', 0.6, typed: true),
          const StackItemNutrients(
            stackEntryId: 'legacy-missing-unit',
            productName: 'Legacy missing unit',
            ingredients: [
              {'canonical_id': 'nickel', 'name': 'Nickel', 'quantity': 2},
            ],
          ),
        ]);
        final status = scopedChecker
            .check(totals, ageBracket: '19-30', sex: 'Male')
            .single;
        expect(status.total.excludedContributions, hasLength(1));
        expect(status.ulAssessmentIndeterminate, isTrue);
        expect(status.pctOfUl, isNull);
        expect(status.shouldWarn, isFalse);
      },
    );

    test('a positive catalog concern survives mixed unknown form scope', () {
      final totals = aggregator.aggregate([
        _ulItem('typed', 'nickel', 0.6, typed: true),
        _ulItem('legacy', 'nickel', 2),
      ]);
      final status = scopedChecker
          .check(
            totals,
            ageBracket: '19-30',
            sex: 'Male',
            pipelineVerdicts: const {
              'nickel': PipelineUlVerdict(overUl: true, pctUl: 120, ul: 1),
            },
          )
          .single;
      expect(status.tier, NutrientTier.exceedsUl);
      expect(status.shouldWarn, isTrue);
      expect(status.warning, isNotNull);
      expect(status.ulAssessmentIndeterminate, isTrue);
      expect(status.pctOfUl, isNull);
    });

    test('a positive catalog concern survives an unreadable legacy unit', () {
      final totals = aggregator.aggregate([
        const StackItemNutrients(
          stackEntryId: 'legacy-unit',
          productName: 'Legacy unit',
          ingredients: [
            {
              'canonical_id': 'nickel',
              'name': 'Nickel',
              'quantity': 2,
              'unit': 'IU',
            },
          ],
        ),
      ]);
      final status = scopedChecker
          .check(
            totals,
            ageBracket: '19-30',
            sex: 'Male',
            pipelineVerdicts: const {
              'nickel': PipelineUlVerdict(overUl: true, pctUl: 120, ul: 1),
            },
          )
          .single;
      expect(status.tier, NutrientTier.exceedsUl);
      expect(status.shouldWarn, isTrue);
      expect(status.ulAssessmentIndeterminate, isTrue);
      expect(status.pctOfUl, isNull);
    });

    test('unscoped zinc retains exact legacy and mixed stack math', () {
      for (final typed in [false, true]) {
        final totals = aggregator.aggregate([
          _ulItem('first', 'zinc', 20, typed: typed),
          _ulItem('legacy', 'zinc', 25),
        ]);
        final status = scopedChecker
            .check(totals, ageBracket: '19-30', sex: 'Male')
            .single;
        expect(status.total.totalAmount, 45);
        expect(status.pctOfUl, 112.5);
        expect(status.tier, NutrientTier.exceedsUl);
        expect(status.ulAssessmentIndeterminate, isFalse);
      }
    });
  });

  test(
    'age-only adolescent keeps its available limit, marked not personal',
    () {
      final status = checker.check({
        'zinc': _total('zinc', 36),
      }, ageBracket: '14-18').single;
      expect(status.ul, 34);
      expect(status.pctOfUl, closeTo(105.882, 0.001));
      expect(status.tier, NutrientTier.exceedsUl);
      expect(status.ulIsFallback, isTrue);
    },
  );

  test('catalog percentage without its limit is marked not personal', () {
    final status = checker
        .check(
          {'calcium': _total('calcium', 900)},
          ageBracket: '19-30',
          sex: 'Female',
          pipelineVerdicts: const {
            'calcium': PipelineUlVerdict(overUl: true, pctUl: 105),
          },
        )
        .single;
    expect(status.ul, isNull);
    expect(status.pctOfUl, 105);
    expect(status.tier, NutrientTier.exceedsUl);
    expect(status.ulIsFallback, isTrue);
  });

  test(
    'unpaired catalog percent preserves a stronger verified personal total',
    () {
      final status = checker
          .check(
            {'calcium': _total('calcium', 5000)},
            ageBracket: '19-30',
            sex: 'Female',
            pipelineVerdicts: const {
              'calcium': PipelineUlVerdict(overUl: true, pctUl: 105),
            },
          )
          .single;
      expect(status.ul, 2500);
      expect(status.pctOfUl, 200);
      expect(status.tier, NutrientTier.exceedsUl);
      expect(status.ulIsFallback, isFalse);
    },
  );

  test(
    'boolean-only catalog concern does not label a personal percent as excess',
    () {
      final status = checker
          .check(
            {'calcium': _total('calcium', 900)},
            ageBracket: '19-30',
            sex: 'Female',
            pipelineVerdicts: const {
              'calcium': PipelineUlVerdict(overUl: true),
            },
          )
          .single;
      expect(status.ul, isNull);
      expect(status.pctOfUl, isNull);
      expect(status.tier, NutrientTier.exceedsUl);
      expect(status.ulIsFallback, isTrue);
    },
  );

  test('boolean-only catalog concern keeps a proven personal breach', () {
    final status = checker
        .check(
          {'calcium': _total('calcium', 5000)},
          ageBracket: '19-30',
          sex: 'Female',
          pipelineVerdicts: const {'calcium': PipelineUlVerdict(overUl: true)},
        )
        .single;
    expect(status.ul, 2500);
    expect(status.pctOfUl, 200);
    expect(status.tier, NutrientTier.exceedsUl);
    expect(status.ulIsFallback, isFalse);
  });

  test(
    'profile edits and clearing refresh the watched personal comparison',
    () {
      final notifier = ProfileNotifier();
      final container = ProviderContainer(
        overrides: [profileProvider.overrideWith((ref) => notifier)],
      );
      addTearDown(container.dispose);
      final statusProvider = Provider((ref) {
        final profile = ref.watch(profileProvider);
        return checker
            .check(
              {'calcium': _total('calcium', 5000)},
              ageBracket: profile.ageBracket,
              sex: profile.sex,
            )
            .single;
      });
      notifier.setAgeBracket('19-30');
      notifier.setSex('Female');
      expect(container.read(statusProvider).pctOfUl, 200);
      expect(container.read(statusProvider).ulIsFallback, isFalse);
      notifier.setAgeBracket(null);
      final clearedAge = container.read(statusProvider);
      expect(clearedAge.pctOfUl, 250);
      expect(clearedAge.ul, 2000);
      expect(clearedAge.ulIsFallback, isTrue);
      notifier.setSex(null);
      expect(container.read(statusProvider).ulIsFallback, isTrue);
      expect(container.read(statusProvider).pctOfUl, 250);
      notifier.setAgeBracket('19-30');
      notifier.setSex('Female');
      expect(container.read(statusProvider).pctOfUl, 200);
      expect(container.read(statusProvider).ulIsFallback, isFalse);
    },
  );

  test('legacy unverified quantity cannot override a catalog concern', () {
    final status = checker
        .check(
          {
            'calcium': const NutrientTotal(
              canonicalId: 'calcium',
              displayName: 'Calcium',
              totalAmount: 5000,
              unit: 'mg',
              contributions: [],
            ),
          },
          ageBracket: '19-30',
          sex: 'Female',
          pipelineVerdicts: const {
            'calcium': PipelineUlVerdict(overUl: true, pctUl: 105),
          },
        )
        .single;
    expect(status.ul, isNull);
    expect(status.pctOfUl, 105);
    expect(status.ulIsFallback, isTrue);
    expect(status.tier, NutrientTier.exceedsUl);
  });

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
  hasUlExposureContract: true,
  ulComparableTotalAmount: amount,
  ulComparableUnit: 'mg',
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

StackItemNutrients _ulItem(
  String id,
  String canonical,
  double amount, {
  bool typed = false,
}) => StackItemNutrients(
  stackEntryId: id,
  productName: id,
  ingredients: [
    {
      'canonical_id': canonical,
      'name': canonical,
      'quantity': amount,
      'unit': 'mg',
      if (typed) ...{
        'ul_gate_eligible': true,
        'safety_exposure': {'per_day': amount, 'unit': 'mg'},
      },
    },
  ],
);
