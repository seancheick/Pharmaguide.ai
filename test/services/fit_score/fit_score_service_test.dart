import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2c_medical_calculator.dart';
import 'package:pharmaguide/services/fit_score/fit_score_service.dart';

void main() {
  group('FitScoreService', () {
    test('calculates combined score with full profile', () {
      final service = FitScoreService(
        e1: E1DosageCalculator({'nutrient_recommendations': []}),
        e2a: E2aGoalCalculator({'user_goal_mappings': []}),
        e2b: E2bAgeCalculator({'nutrient_recommendations': []}),
        e2c: E2cMedicalCalculator(),
      );

      final result = service.calculate(
        scoreQuality80: 65.0,
        nutrients: [],
        productClusters: [],
        interactionSummary: {},
        ageBracket: '19-30',
        sex: 'Male',
        userGoals: ['GOAL_SLEEP_QUALITY'],
      );

      // E1: 0 (no nutrients), E2a: 0 (no clusters), E2b: 0 (no nutrients), E2c: 8.0 (no interactions)
      expect(result.e2c, 8.0);
      expect(result.scoreFit20, 8.0);
      expect(result.scoreCombined100, 73.0); // (65 + 8) * 100 / 100
    });

    test('reports missing fields', () {
      final service = FitScoreService(
        e1: E1DosageCalculator({'nutrient_recommendations': []}),
        e2a: E2aGoalCalculator({'user_goal_mappings': []}),
        e2b: E2bAgeCalculator({'nutrient_recommendations': []}),
        e2c: E2cMedicalCalculator(),
      );

      final result = service.calculate(
        scoreQuality80: 65.0,
        nutrients: [],
        productClusters: [],
        interactionSummary: {},
      );

      expect(result.missingFields, contains('age'));
      expect(result.missingFields, contains('sex'));
      expect(result.missingFields, contains('goals'));
    });

    test('maxPossible adjusts based on profile', () {
      final service = FitScoreService(
        e1: E1DosageCalculator({'nutrient_recommendations': []}),
        e2a: E2aGoalCalculator({'user_goal_mappings': []}),
        e2b: E2bAgeCalculator({'nutrient_recommendations': []}),
        e2c: E2cMedicalCalculator(),
      );

      // No profile: max = 80 + 4 + 8 = 92 (E1 baseline mode, no E2a, no E2b)
      final empty = service.calculate(
        scoreQuality80: 65.0,
        nutrients: [],
        productClusters: [],
        interactionSummary: {},
      );
      expect(empty.maxPossible, 92.0);

      // Full profile: max = 80 + 7 + 2 + 3 + 8 = 100
      final full = service.calculate(
        scoreQuality80: 65.0,
        nutrients: [],
        productClusters: [],
        interactionSummary: {},
        ageBracket: '19-30',
        sex: 'Male',
        userGoals: ['GOAL_SLEEP_QUALITY'],
      );
      expect(full.maxPossible, 100.0);
    });

    test('maxPossible reflects degraded E1 behavior when age exists without sex', () {
      final service = FitScoreService(
        e1: E1DosageCalculator({'nutrient_recommendations': <Object>[]}),
        e2a: E2aGoalCalculator({'user_goal_mappings': <Object>[]}),
        e2b: E2bAgeCalculator({'nutrient_recommendations': <Object>[]}),
        e2c: E2cMedicalCalculator(),
      );

      final partial = service.calculate(
        scoreQuality80: 65.0,
        nutrients: const [],
        productClusters: const [],
        interactionSummary: const {},
        ageBracket: '19-30',
      );

      expect(partial.maxPossible, 91.0);
    });
  });
}
