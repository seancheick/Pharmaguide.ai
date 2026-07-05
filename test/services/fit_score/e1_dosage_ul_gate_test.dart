// E1 dose-score regression tests for the pipeline UL contract
// (`ul_gate_eligible`, `over_ul`, `pct_ul`).
//
// E1DosageCalculator drops the whole dose score to -5 when ANY nutrient
// is classified `exceedsUl`. These tests pin the three cases from the bug
// report:
//
//   (a) A compound-mass row the pipeline declined to gate
//       (`ul_gate_eligible:false`) must NOT trigger the -5 penalty —
//       it is not elemental-comparable to the reference UL.
//   (b) A row the pipeline DID gate and judged over the limit
//       (`over_ul:true` / `pct_ul>=150`) must still trigger -5, even when
//       the client's own recompute (raw quantity / reference) would land
//       under the UL. The pipeline verdict is preferred over recompute.
//   (c) A legit elemental row with no pipeline verdict, disclosed over the
//       UL, must still trigger -5 via the recompute fallback.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';

void main() {
  final calculator = E1DosageCalculator(_rda);

  group('E1DosageCalculator — ul_gate_eligible / pipeline UL verdict', () {
    test('(a) Magtein-alone compound mass (ul_gate_eligible:false) does NOT '
        'drop the dose score to -5', () {
      final score = calculator.calculate(
        nutrients: const [
          {
            'mapped_name': 'magnesium',
            'standard_name': 'Magnesium L-Threonate',
            'name': 'Magnesium L-Threonate',
            'quantity': 2000,
            'unit': 'mg',
            'ul_gate_eligible': false,
            'ul_gate_ineligible_reason': 'compound_mass_not_elemental',
          },
        ],
        ageBracket: '19-30',
        sex: 'Male',
      );

      // Was falsely -5 (2000 mg compound vs 350 mg elemental UL = 571%).
      expect(score, isNot(-5.0));
      expect(score, 0.0);
    });

    test('(b) pipeline over_ul:true / pct_ul:200 is preferred over a '
        'recompute that would land under the UL → still -5', () {
      final score = calculator.calculate(
        nutrients: const [
          {
            'mapped_name': 'magnesium',
            'standard_name': 'Magnesium',
            'name': 'Magnesium',
            // 100 mg recomputes to ~28% of the 350 mg UL — under the limit.
            'quantity': 100,
            'unit': 'mg',
            'over_ul': true,
            'pct_ul': 200,
            'ul_gate_eligible': true,
          },
        ],
        ageBracket: '19-30',
        sex: 'Male',
      );

      expect(score, -5.0);
    });

    test('(c) legit elemental row over the UL with no pipeline verdict still '
        'penalizes via recompute fallback', () {
      final score = calculator.calculate(
        nutrients: const [
          {
            'mapped_name': 'magnesium',
            'standard_name': 'Magnesium',
            'name': 'Magnesium',
            // 500 mg elemental vs 350 mg UL = 143% → exceedsUl.
            'quantity': 500,
            'unit': 'mg',
          },
        ],
        ageBracket: '19-30',
        sex: 'Male',
      );

      expect(score, -5.0);
    });

    test('pipeline over_ul:false suppresses a recompute that would exceed', () {
      // Eligible row the pipeline computed as within-UL, but whose raw
      // compound-ish quantity would recompute over. Prefer the verdict.
      final score = calculator.calculate(
        nutrients: const [
          {
            'mapped_name': 'magnesium',
            'standard_name': 'Magnesium',
            'name': 'Magnesium',
            'quantity': 2000,
            'unit': 'mg',
            'over_ul': false,
            'ul_gate_eligible': true,
          },
        ],
        ageBracket: '19-30',
        sex: 'Male',
      );

      expect(score, isNot(-5.0));
    });
  });
}

const _rda = {
  'nutrient_recommendations': [
    {
      'id': 'magnesium',
      'standard_name': 'Magnesium',
      'unit': 'mg',
      // Supplemental magnesium UL (IOM) = 350 mg elemental.
      'highest_ul': 350,
      'data': [
        {'group': 'Male', 'age_range': '19-30', 'rda_ai': 400, 'ul': 350},
        {'group': 'Female', 'age_range': '19-30', 'rda_ai': 310, 'ul': 350},
      ],
    },
  ],
};
