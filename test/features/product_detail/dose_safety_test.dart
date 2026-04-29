// FLTR-11 — Dose-vs-UL safety.
//
// Covers [resolveDoseSafety] and [matchUlEntry] against the real
// blob schema emitted by the pipeline (rda_ul_data.analyzed_ingredients),
// including the three behavioral states the UI must render:
//
//   DoseSafety.exceedsUl    — disclosed dose > UL (skip_ul_check false)
//   DoseSafety.skip         — pipeline opted out of UL evaluation
//   DoseSafety.withinLimits — no UL concern / no matching entry / no UL
//
// Policy per handoff §0: the UI interprets the pipeline decision
// verbatim. When the pipeline sets skip_ul_check=true, the UI must
// not substitute "Excellent" or "High dose" — it shows a neutral
// "dose not evaluated" state.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/dose_safety.dart';

void main() {
  group('resolveDoseSafety', () {
    test('Niacin 50 mg vs UL 35 mg with skip_ul_check=false → exceedsUl', () {
      final ingredient = <String, dynamic>{
        'name': 'Vitamin B3 (Niacin)',
        'standard_name': 'Vitamin B3 (Niacin)',
        'quantity': 50.0,
        'unit': 'mg',
      };
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Vitamin B3 (Niacin)',
          'quantity': 50.0,
          'unit': 'mg',
          'skip_ul_check': false,
          'ul_for_default_profile': 35,
          'highest_ul': 35,
        },
      ];
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
        DoseSafety.exceedsUl,
      );
    });

    test(
      'skip_ul_check=true always returns skip even when dose exceeds UL',
      () {
        // Thorne Vitamin A 25,000 IU — pipeline sets skip_ul_check=true
        // with skip_ul_reason "unknown_vitamin_form". UI must NOT render
        // an override, even though 25,000 IU is clearly above 10,000 IU.
        // The pipeline owns the clinical decision.
        final ingredient = <String, dynamic>{
          'name': 'Vitamin A',
          'standard_name': 'Vitamin A',
          'quantity': 25000.0,
          'unit': 'IU',
        };
        final ulAnalysis = <Map<String, dynamic>>[
          {
            'standard_name': 'Vitamin A',
            'quantity': 25000.0,
            'unit': 'IU',
            'skip_ul_check': true,
            'skip_ul_reason': 'unknown_vitamin_form',
            'ul_for_default_profile': null,
            'highest_ul': 3000,
          },
        ];
        expect(
          resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
          DoseSafety.skip,
        );
      },
    );

    test('safe dose under UL returns withinLimits', () {
      final ingredient = <String, dynamic>{
        'standard_name': 'Vitamin D3',
        'quantity': 1000.0,
        'unit': 'IU',
      };
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Vitamin D3',
          'quantity': 1000.0,
          'unit': 'IU',
          'skip_ul_check': false,
          'ul_for_default_profile': 4000,
          'highest_ul': 4000,
        },
      ];
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
        DoseSafety.withinLimits,
      );
    });

    test('dose exactly at UL is not over — strict >', () {
      final ingredient = <String, dynamic>{
        'standard_name': 'Zinc',
        'quantity': 40.0,
      };
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Zinc',
          'quantity': 40.0,
          'skip_ul_check': false,
          'ul_for_default_profile': 40,
          'highest_ul': 40,
        },
      ];
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
        DoseSafety.withinLimits,
      );
    });

    test('prefers ul_for_default_profile over highest_ul', () {
      // Age/sex-aware UL is stricter than the worst-case fallback.
      // When both are present, the profile UL is the one that fires.
      final ingredient = <String, dynamic>{'standard_name': 'Iron'};
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Iron',
          'quantity': 30.0,
          'skip_ul_check': false,
          'ul_for_default_profile': 25,
          'highest_ul': 45,
        },
      ];
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
        DoseSafety.exceedsUl,
      );
    });

    test('falls back to highest_ul when ul_for_default_profile is null', () {
      final ingredient = <String, dynamic>{'standard_name': 'Vitamin A'};
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Vitamin A',
          'quantity': 15000.0,
          'skip_ul_check': false,
          'ul_for_default_profile': null,
          'highest_ul': 10000,
        },
      ];
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
        DoseSafety.exceedsUl,
      );
    });

    test('null ulAnalysis returns withinLimits (no override)', () {
      final ingredient = <String, dynamic>{
        'standard_name': 'Vitamin A',
        'quantity': 25000.0,
      };
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: null),
        DoseSafety.withinLimits,
      );
    });

    test('empty ulAnalysis returns withinLimits', () {
      final ingredient = <String, dynamic>{
        'standard_name': 'Vitamin A',
        'quantity': 25000.0,
      };
      expect(
        resolveDoseSafety(
          ingredient: ingredient,
          ulAnalysis: const <Map<String, dynamic>>[],
        ),
        DoseSafety.withinLimits,
      );
    });

    test('no matching entry in ulAnalysis returns withinLimits', () {
      final ingredient = <String, dynamic>{'standard_name': 'Magnesium'};
      final ulAnalysis = <Map<String, dynamic>>[
        {'standard_name': 'Vitamin A', 'quantity': 5000, 'highest_ul': 10000},
      ];
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
        DoseSafety.withinLimits,
      );
    });

    test('missing quantity returns withinLimits (incomplete data)', () {
      final ingredient = <String, dynamic>{'standard_name': 'Vitamin D'};
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Vitamin D',
          'quantity': null,
          'skip_ul_check': false,
          'highest_ul': 4000,
        },
      ];
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
        DoseSafety.withinLimits,
      );
    });

    test('missing UL returns withinLimits (no UL data to compare)', () {
      final ingredient = <String, dynamic>{'standard_name': 'Vitamin B12'};
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Vitamin B12',
          'quantity': 5000,
          'skip_ul_check': false,
          // No ul_for_default_profile or highest_ul — B12 has no UL.
        },
      ];
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
        DoseSafety.withinLimits,
      );
    });

    test('does NOT use per_day_max (handoff clarification)', () {
      // Using per_day_max would double-count the serving math: a
      // label allowing 2 servings/day would push "1 serving worth of
      // dose" over UL and fire a false positive. We compare the
      // disclosed quantity, not the aggregated daily intake.
      final ingredient = <String, dynamic>{'standard_name': 'Zinc'};
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Zinc',
          'quantity': 20.0, // below UL 40
          'per_day_max': 80.0, // above UL only when doubled
          'skip_ul_check': false,
          'ul_for_default_profile': 40,
          'highest_ul': 40,
        },
      ];
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
        DoseSafety.withinLimits,
        reason: 'per_day_max must not trigger UL — use quantity',
      );
    });

    test('matching is case-insensitive and whitespace-tolerant', () {
      final ingredient = <String, dynamic>{
        'standard_name': '  vitamin B3 (NIACIN)  ',
      };
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Vitamin B3 (Niacin)',
          'quantity': 50.0,
          'skip_ul_check': false,
          'ul_for_default_profile': 35,
          'highest_ul': 35,
        },
      ];
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
        DoseSafety.exceedsUl,
      );
    });

    test('falls back to ingredient/name when standard_name missing', () {
      final ingredient = <String, dynamic>{'name': 'Iron'};
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'ingredient': 'Iron',
          'quantity': 50.0,
          'skip_ul_check': false,
          'ul_for_default_profile': 45,
          'highest_ul': 45,
        },
      ];
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
        DoseSafety.exceedsUl,
      );
    });
  });

  group('extractUlExceedances (FLTR-5)', () {
    test('returns one UlExceedance per warning string', () {
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Vitamin B3 (Niacin)',
          'quantity': 50.0,
          'skip_ul_check': false,
          'warnings': ['Exceeds UL by 15.0 mg'],
        },
      ];
      final out = extractUlExceedances(ulAnalysis);
      expect(out, hasLength(1));
      expect(out.first.standardName, 'Vitamin B3 (Niacin)');
      expect(out.first.warning, 'Exceeds UL by 15.0 mg');
    });

    test('skips entries with skip_ul_check=true', () {
      // Thorne Vitamin A case — pipeline opted out of UL evaluation.
      // UI must not surface a synthesized alert in this state.
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Vitamin A',
          'quantity': 25000.0,
          'skip_ul_check': true,
          'warnings': ['This warning should not surface'],
        },
      ];
      expect(extractUlExceedances(ulAnalysis), isEmpty);
    });

    test('skips entries with empty warnings list', () {
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Vitamin D3',
          'skip_ul_check': false,
          'warnings': <Object>[],
        },
      ];
      expect(extractUlExceedances(ulAnalysis), isEmpty);
    });

    test('emits one UlExceedance per warning when multiple exist', () {
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Iron',
          'skip_ul_check': false,
          'warnings': [
            'Exceeds UL by 5.0 mg',
            'May mask zinc deficiency at this dose',
          ],
        },
      ];
      final out = extractUlExceedances(ulAnalysis);
      expect(out, hasLength(2));
      expect(out[0].warning, 'Exceeds UL by 5.0 mg');
      expect(out[1].warning, contains('zinc deficiency'));
    });

    test('falls back to ingredient field when standard_name is missing', () {
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'ingredient': 'Zinc',
          'skip_ul_check': false,
          'warnings': ['Exceeds UL'],
        },
      ];
      final out = extractUlExceedances(ulAnalysis);
      expect(out.first.standardName, 'Zinc');
    });

    test('handles null / empty / malformed input without throwing', () {
      expect(extractUlExceedances(null), isEmpty);
      expect(extractUlExceedances(const []), isEmpty);
      expect(
        extractUlExceedances([
          {
            'standard_name': '',
            'warnings': ['x'],
          },
          {'standard_name': 'A', 'warnings': 'not-a-list'},
          {
            'standard_name': 'B',
            'warnings': ['', ' ', 'valid'],
          },
        ]),
        hasLength(1),
        reason:
            'Empty names, non-list warnings, and blank strings must '
            'be filtered out; only the "valid" entry remains.',
      );
    });
  });

  group('matchUlEntry', () {
    test('returns matched entry when standard_name matches', () {
      final ingredient = <String, dynamic>{'standard_name': 'Vitamin D3'};
      final ulAnalysis = <Map<String, dynamic>>[
        {'standard_name': 'Vitamin D3', 'quantity': 2000},
        {'standard_name': 'Vitamin A', 'quantity': 5000},
      ];
      final match = matchUlEntry(ingredient, ulAnalysis);
      expect(match, isNotNull);
      expect(match!['quantity'], 2000);
    });

    test('returns null when no match', () {
      final ingredient = <String, dynamic>{'standard_name': 'Magnesium'};
      final ulAnalysis = <Map<String, dynamic>>[
        {'standard_name': 'Vitamin A'},
      ];
      expect(matchUlEntry(ingredient, ulAnalysis), isNull);
    });

    test('returns null when ulAnalysis is null or empty', () {
      final ingredient = <String, dynamic>{'standard_name': 'Vitamin A'};
      expect(matchUlEntry(ingredient, null), isNull);
      expect(matchUlEntry(ingredient, const []), isNull);
    });
  });

  // -----------------------------------------------------------------------
  // FLTR-11a test groups RETIRED (2026-04-24) — pipeline E1.11 now emits
  // dose-aware severity at source. The downgradeIfLowDose() and
  // indexIngredientsByStandardName() helpers have been deleted from
  // dose_safety.dart along with their tests. Coverage is now enforced
  // by scripts/tests/test_*.py on the pipeline side.
  // -----------------------------------------------------------------------
}
