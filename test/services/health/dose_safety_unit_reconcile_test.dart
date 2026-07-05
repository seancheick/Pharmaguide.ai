// P2 hardening: unit reconciliation in the legacy quantity-vs-UL fallback
// (`_quantityExceedsResolvedUl`, reached only when a row carries NO
// structured `over_ul`/`pct_ul` decision).
//
// The old code compared `entry['quantity']` to the resolved UL with NO
// unit reconciliation. An entry disclosing 150 mcg of Boron against a UL
// expressed as 20 mg would read 150 > 20 → a false exceedance. The UL's
// unit is the nutrient reference unit (`nutrient_unit` / `converted_unit`);
// the quantity's unit is `unit`. Reconcile simple metric mass before the
// compare, and NEVER compare across unreconcilable units.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/health/dose_safety.dart';

void main() {
  group('resolveDoseSafety — legacy quantity/UL unit reconciliation', () {
    test('Boron 150 mcg vs 20 mg UL reconciles → withinLimits (no false over)',
        () {
      final ingredient = <String, dynamic>{
        'standard_name': 'Boron',
        'quantity': 150.0,
        'unit': 'mcg',
      };
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Boron',
          'quantity': 150.0,
          'unit': 'mcg',
          'nutrient_unit': 'mg',
          'skip_ul_check': false,
          'highest_ul': 20,
          // No over_ul / pct_ul → legacy recompute path.
        },
      ];
      expect(
        resolveDoseSafety(ingredient: ingredient, ulAnalysis: ulAnalysis),
        DoseSafety.withinLimits,
        reason: '150 mcg = 0.15 mg is well under the 20 mg UL',
      );
    });

    test('genuine same-unit exceedance still fires (25 mg vs 20 mg UL)', () {
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Boron',
          'quantity': 25.0,
          'unit': 'mg',
          'nutrient_unit': 'mg',
          'skip_ul_check': false,
          'highest_ul': 20,
        },
      ];
      expect(
        resolveDoseSafety(
          ingredient: const {'standard_name': 'Boron'},
          ulAnalysis: ulAnalysis,
        ),
        DoseSafety.exceedsUl,
      );
    });

    test('reconciled cross-unit exceedance fires (25000 mcg vs 20 mg UL)', () {
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Boron',
          'quantity': 25000.0,
          'unit': 'mcg',
          'nutrient_unit': 'mg',
          'skip_ul_check': false,
          'highest_ul': 20,
        },
      ];
      expect(
        resolveDoseSafety(
          ingredient: const {'standard_name': 'Boron'},
          ulAnalysis: ulAnalysis,
        ),
        DoseSafety.exceedsUl,
        reason: '25000 mcg = 25 mg exceeds the 20 mg UL',
      );
    });

    test('unreconcilable units (IU quantity vs mg UL) never raw-compare → '
        'withinLimits', () {
      final ulAnalysis = <Map<String, dynamic>>[
        {
          'standard_name': 'Vitamin E',
          'quantity': 2000.0,
          'unit': 'IU',
          'nutrient_unit': 'mg',
          'skip_ul_check': false,
          'highest_ul': 1000,
        },
      ];
      expect(
        resolveDoseSafety(
          ingredient: const {'standard_name': 'Vitamin E'},
          ulAnalysis: ulAnalysis,
        ),
        DoseSafety.withinLimits,
        reason: 'IU↔mg is form-dependent; must not be guessed → decline',
      );
    });

    test('absent UL unit preserves legacy same-unit compare (Niacin 50>35)',
        () {
      // Existing blobs omit nutrient_unit; behavior must be unchanged.
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
        resolveDoseSafety(
          ingredient: const {'standard_name': 'Vitamin B3 (Niacin)'},
          ulAnalysis: ulAnalysis,
        ),
        DoseSafety.exceedsUl,
      );
    });
  });
}
