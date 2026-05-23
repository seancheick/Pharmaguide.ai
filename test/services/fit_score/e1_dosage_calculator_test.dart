import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';

void main() {
  group('E1DosageCalculator', () {
    final calculator = E1DosageCalculator(_rdaFixture);

    test('uses pipeline daily converted amount and B-vitamin aliases', () {
      final score = calculator.calculate(
        nutrients: const [
          {
            'mapped_name': 'vitamin_b3_niacin',
            'standard_name': 'Vitamin B3 (Niacin)',
            'per_day_max': 40,
            'daily_amount_unit': 'mg NE',
          },
        ],
        ageBracket: '19-30',
        sex: 'Male',
      );

      expect(score, -5.0);
    });

    test('uses pregnancy demographic RDA when caller supplies Pregnancy', () {
      final score = calculator.calculate(
        nutrients: const [
          {
            'mapped_name': 'vitamin_b9_folate',
            'standard_name': 'Folate',
            'per_day_max': 600,
            'daily_amount_unit': 'mcg DFE',
          },
        ],
        ageBracket: '19-30',
        sex: 'Pregnancy',
      );

      expect(score, 7.0);
    });

    test('does not compare incompatible units against RDA or UL', () {
      final score = calculator.calculate(
        nutrients: const [
          {
            'mapped_name': 'zinc',
            'standard_name': 'Zinc',
            'quantity': 40000,
            'unit': 'IU',
          },
        ],
        ageBracket: '19-30',
        sex: 'Male',
      );

      expect(score, 0.0);
    });

    test('anonymous users still get least-restrictive UL overage fallback', () {
      final score = calculator.calculate(
        nutrients: const [
          {
            'mapped_name': 'zinc',
            'standard_name': 'Zinc',
            'quantity': 45,
            'unit': 'mg',
          },
        ],
      );

      expect(score, -5.0);
    });

    test('non-RDA therapeutic ingredients are not scored as nutrients', () {
      final score = calculator.calculate(
        nutrients: const [
          {
            'mapped_name': 'ashwagandha_root_extract',
            'standard_name': 'Ashwagandha Root Extract',
            'quantity': 600,
            'unit': 'mg',
          },
        ],
        ageBracket: '19-30',
        sex: 'Male',
      );

      expect(score, 0.0);
    });

    test('scores ALA after mg to g normalization but ignores EPA', () {
      final score = calculator.calculate(
        nutrients: const [
          {
            'mapped_name': 'alpha_linolenic_acid',
            'standard_name': 'Alpha-Linolenic Acid',
            'per_day_max': 1600,
            'daily_amount_unit': 'mg',
          },
          {
            'mapped_name': 'epa',
            'standard_name': 'EPA (Eicosapentaenoic Acid)',
            'per_day_max': 1000,
            'daily_amount_unit': 'mg',
          },
        ],
        ageBracket: '19-30',
        sex: 'Male',
      );

      expect(score, 7.0);
    });
  });
}

const _rdaFixture = {
  'nutrient_recommendations': [
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
      'id': 'niacin',
      'standard_name': 'Niacin',
      'unit': 'mg NE',
      'highest_ul': 35,
      'data': [
        {'group': 'Male', 'age_range': '19-30', 'rda_ai': 16, 'ul': 35},
      ],
    },
    {
      'id': 'folate',
      'standard_name': 'Folate',
      'unit': 'mcg DFE',
      'highest_ul': 1667,
      'data': [
        {'group': 'Female', 'age_range': '19-30', 'rda_ai': 400, 'ul': 1667},
        {'group': 'Pregnancy', 'age_range': '19-30', 'rda_ai': 600, 'ul': 1667},
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
  ],
};
