import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/fit_score/e2c_medical_calculator.dart';

void main() {
  late E2cMedicalCalculator calc;
  setUp(() => calc = E2cMedicalCalculator());

  group('E2cMedicalCalculator', () {
    test('returns 8.0 when no conditions match', () {
      final score = calc.calculate(
        interactionSummary: const <String, dynamic>{
          'condition_summary': <String, dynamic>{},
          'drug_class_summary': <String, dynamic>{},
        },
        userConditions: const ['diabetes'],
        userDrugClasses: const ['statins'],
      );
      expect(score, 8.0);
    });

    test('penalizes contraindicated condition with -8', () {
      final score = calc.calculate(
        interactionSummary: const <String, dynamic>{
          'condition_summary': <String, dynamic>{
            'pregnancy': <String, dynamic>{
              'highest_severity': 'contraindicated',
            },
          },
          'drug_class_summary': <String, dynamic>{},
        },
        userConditions: const ['pregnancy'],
        userDrugClasses: const [],
      );
      expect(score, 0.0); // 8 - 8 = 0
    });

    test('penalizes avoid drug class with -5', () {
      final score = calc.calculate(
        interactionSummary: const <String, dynamic>{
          'condition_summary': <String, dynamic>{},
          'drug_class_summary': <String, dynamic>{
            'anticoagulants': <String, dynamic>{'highest_severity': 'avoid'},
          },
        },
        userConditions: const [],
        userDrugClasses: const ['anticoagulants'],
      );
      expect(score, 3.0); // 8 - 5 = 3
    });

    test('handles multiple conditions and drug classes', () {
      final score = calc.calculate(
        interactionSummary: const <String, dynamic>{
          'condition_summary': <String, dynamic>{
            'pregnancy': <String, dynamic>{'highest_severity': 'caution'}, // -3
            'diabetes': <String, dynamic>{'highest_severity': 'monitor'}, // -1
          },
          'drug_class_summary': <String, dynamic>{
            'statins': <String, dynamic>{'highest_severity': 'caution'}, // -3
          },
        },
        userConditions: const ['pregnancy', 'diabetes'],
        userDrugClasses: const ['statins'],
      );
      expect(score, 1.0); // 8 - 3 - 1 - 3 = 1
    });

    test('clamps to 0 when penalties exceed 8', () {
      final score = calc.calculate(
        interactionSummary: const <String, dynamic>{
          'condition_summary': <String, dynamic>{
            'pregnancy': <String, dynamic>{
              'highest_severity': 'contraindicated',
            },
          },
          'drug_class_summary': <String, dynamic>{
            'anticoagulants': <String, dynamic>{'highest_severity': 'avoid'},
          },
        },
        userConditions: const ['pregnancy'],
        userDrugClasses: const ['anticoagulants'],
      );
      expect(score, 0.0); // 8 - 8 - 5 = -5, clamped to 0
    });

    test('returns 8.0 with empty profile', () {
      final score = calc.calculate(
        interactionSummary: const <String, dynamic>{},
        userConditions: const [],
        userDrugClasses: const [],
      );
      expect(score, 8.0);
    });
  });
}
