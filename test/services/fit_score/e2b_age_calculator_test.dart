import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';

void main() {
  group('E2bAgeCalculator', () {
    final calculator = E2bAgeCalculator(_rdaFixture);

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

      expect(score, 3.0);
    });

    test('uses sex-specific RDA when sex is supplied', () {
      final female = calculator.calculate(
        nutrients: const [
          {
            'mapped_name': 'iron',
            'standard_name': 'Iron',
            'quantity': 45,
            'unit': 'mg',
          },
        ],
        ageBracket: '19-30',
        sex: 'Female',
      );
      final male = calculator.calculate(
        nutrients: const [
          {
            'mapped_name': 'iron',
            'standard_name': 'Iron',
            'quantity': 45,
            'unit': 'mg',
          },
        ],
        ageBracket: '19-30',
        sex: 'Male',
      );

      expect(female, 3.0);
      expect(male, 0.0);
    });

    test('does not score incompatible units as age-appropriate', () {
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
      'id': 'niacin',
      'standard_name': 'Niacin',
      'unit': 'mg NE',
      'highest_ul': 35,
      'data': [
        {'group': 'Male', 'age_range': '19-30', 'rda_ai': 16, 'ul': 35},
      ],
    },
  ],
};
