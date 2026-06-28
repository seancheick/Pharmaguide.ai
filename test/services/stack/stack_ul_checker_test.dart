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
      final totals = _totals([_total('magnesium', 'Magnesium', 500, 'mg')]);
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

    test(
      'anonymous user with null age/sex still gets UL check via highest_ul',
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
      expect(results.first.ul, 40);
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
    test('zinc excess warns copper depletion with chronic-dose action', () {
      final results = checker.check(
        _totals([_total('zinc', 'Zinc', 60, 'mg')]),
        ageBracket: '19-30',
        sex: 'Male',
      );
      final warning = results.first.warning;
      expect(warning, contains('copper depletion'));
      // Cumulative-dose framing (IOM Zn UL 40 mg/d; PMID 18525032), not a
      // "space apart" timing tip, plus actionable guidance.
      expect(warning, contains('over time'));
      expect(warning, contains('copper alongside'));
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
