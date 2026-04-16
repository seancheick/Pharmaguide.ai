// Tests for [StackUlChecker].
//
// Uses a hand-built minimal RDA fixture that mirrors the real
// `rda_optimal_uls.json` shape (id, standard_name, highest_ul,
// data[{group, age_range, rda_ai, ul}]). Keeping the fixture
// inline makes each test easy to read in isolation and avoids the
// root-bundle asset loader which needs a widget test context.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_ul_checker.dart';

void main() {
  // Minimal fixture matching the real reference data contract.
  final rdaFixture = {
    '_metadata': {'schema_version': '5.0.0'},
    'nutrient_recommendations': [
      {
        'id': 'vitamin_d3',
        'standard_name': 'Vitamin D3',
        'highest_ul': 4000,
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 600, 'ul': 4000},
          {
            'group': 'Female',
            'age_range': '19-30',
            'rda_ai': 600,
            'ul': 4000
          },
          {'group': 'Male', 'age_range': '31-50', 'rda_ai': 600, 'ul': 4000},
        ],
      },
      {
        'id': 'zinc',
        'standard_name': 'Zinc',
        'highest_ul': 40,
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 11, 'ul': 40},
          {'group': 'Female', 'age_range': '19-30', 'rda_ai': 8, 'ul': 40},
        ],
      },
      {
        'id': 'magnesium',
        'standard_name': 'Magnesium',
        'highest_ul': 350,
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 400, 'ul': 350},
          {'group': 'Female', 'age_range': '19-30', 'rda_ai': 310, 'ul': 350},
        ],
      },
      {
        'id': 'iron',
        'standard_name': 'Iron',
        'highest_ul': 45,
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 8, 'ul': 45},
          {'group': 'Female', 'age_range': '19-30', 'rda_ai': 18, 'ul': 45},
        ],
      },
      {
        // Entry with no UL at all — e.g. some B vitamins.
        'id': 'vitamin_b12',
        'standard_name': 'Vitamin B12',
        'data': [
          {'group': 'Male', 'age_range': '19-30', 'rda_ai': 2.4},
          {'group': 'Female', 'age_range': '19-30', 'rda_ai': 2.4},
        ],
      },
    ],
  };

  final checker = StackUlChecker(rdaData: rdaFixture);

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
      expect(results.first.warning, contains('copper depletion'));
      expect(results.first.shouldWarn, isTrue);
    });

    test('UL precedence: exceedsUl wins over abundant RDA', () {
      // Magnesium male: RDA=400, UL=350. Total=500 → 125% RDA but 143% UL
      // Result must be exceedsUl, not abundant.
      final totals =
          _totals([_total('magnesium', 'Magnesium', 500, 'mg')]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.tier, NutrientTier.exceedsUl);
    });
  });

  group('StackUlChecker — demographic lookup', () {
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

    test('anonymous user with null age/sex still gets UL check via highest_ul',
        () {
      final totals = _totals([_total('zinc', 'Zinc', 45, 'mg')]);
      final results = checker.check(totals);
      // Anonymous users now receive a baseline RDA (Female 19-30) so
      // %RDA displays without a profile. UL check still dominates —
      // 45mg > 40mg UL takes precedence over any RDA-based tiering.
      expect(results.first.rda, 8.0);
      expect(results.first.rdaIsBaseline, isTrue);
      expect(results.first.ul, 40);
      expect(results.first.tier, NutrientTier.exceedsUl);
      expect(results.first.warning, contains('copper depletion'));
    });

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
      final results = checker.check(
        totals,
        ageBracket: '19-30',
        sex: 'Male',
      );
      // Profile match should set rdaIsBaseline = false so the UI
      // renders the value without the "*" hint.
      expect(results.first.rda, isNotNull);
      expect(results.first.rdaIsBaseline, isFalse);
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
  });

  group('StackUlChecker — nutrients with no UL', () {
    test('vitamin B12 (no UL) classifies purely by RDA', () {
      final totals = _totals([
        _total('vitamin_b12', 'Vitamin B12', 5, 'mcg'),
      ]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      // RDA=2.4, 5mcg = 208% RDA, no UL → aboveTypical
      expect(results.first.tier, NutrientTier.aboveTypical);
      expect(results.first.ul, isNull);
    });

    test('vitamin B12 at RDA level shows abundant', () {
      final totals = _totals([
        _total('vitamin_b12', 'Vitamin B12', 2.4, 'mcg'),
      ]);
      final results = checker.check(totals, ageBracket: '19-30', sex: 'Male');
      expect(results.first.tier, NutrientTier.abundant);
    });
  });

  group('StackUlChecker — warning strings', () {
    test('zinc excess produces copper depletion warning', () {
      final results = checker.check(
        _totals([_total('zinc', 'Zinc', 60, 'mg')]),
        ageBracket: '19-30',
        sex: 'Male',
      );
      expect(results.first.warning,
          contains('copper depletion'));
    });

    test('iron excess produces GI/oxidative warning', () {
      final results = checker.check(
        _totals([_total('iron', 'Iron', 50, 'mg')]),
        ageBracket: '19-30',
        sex: 'Male',
      );
      expect(results.first.warning, contains('GI toxicity'));
    });

    test('unknown canonical id with UL breach still produces a warning', () {
      // Canonical id is deliberately off-schema so the specific
      // warning map misses. The RDA lookup still succeeds via the
      // standard_name fuzzy match, so the tier is correct, and the
      // warning falls back to the safe generic message.
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
      // Generic fallback is the safe answer when we can't map the
      // canonical id to a specific mechanism.
      expect(results.first.warning, contains('Upper Limit'));
    });
  });

  group('StackUlChecker — empty and edge cases', () {
    test('empty aggregation returns empty list', () {
      expect(
        checker.check(<String, NutrientTotal>{}),
        isEmpty,
      );
    });

    test('checker with empty rda data returns noRda for everything', () {
      const emptyChecker = StackUlChecker(rdaData: {
        'nutrient_recommendations': <dynamic>[],
      });
      final results = emptyChecker.check(
        _totals([_total('zinc', 'Zinc', 15, 'mg')]),
      );
      expect(results.first.tier, NutrientTier.noRda);
    });

    test('checker with malformed rda data does not crash', () {
      const brokenChecker = StackUlChecker(rdaData: {
        'nutrient_recommendations': [
          'not a map',
          {'id': 'valid_but_no_data'},
          {'id': 'bad_data', 'data': 'not a list'},
        ],
      });
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
) =>
    NutrientTotal(
      canonicalId: canonicalId,
      displayName: displayName,
      totalAmount: amount,
      unit: unit,
      contributions: const [],
    );
