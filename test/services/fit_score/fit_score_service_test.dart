import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/schema_ids.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/fit_score_service.dart';

void main() {
  group('FitScoreService', () {
    test('returns a categorical assessment with a complete profile', () {
      final service = FitScoreService(
        e1: E1DosageCalculator(const <String, dynamic>{
          'nutrient_recommendations': <dynamic>[],
        }),
        e2a: E2aGoalCalculator(const <String, dynamic>{
          'user_goal_mappings': <dynamic>[],
        }),
        e2b: E2bAgeCalculator(const <String, dynamic>{
          'nutrient_recommendations': <dynamic>[],
        }),
      );

      final result = service.calculate(
        nutrients: const <Map<String, dynamic>>[],
        productClusters: const <String>[],
        interactionSummary: const <String, dynamic>{},
        ageBracket: '19-30',
        sex: 'Male',
        userGoals: ['GOAL_SLEEP_QUALITY'],
      );

      expect(result.state, FitAssessmentState.limitedFit);
      expect(result.maxRelevantSeverity, isNull);
    });

    test('reports missing fields', () {
      final service = FitScoreService(
        e1: E1DosageCalculator(const <String, dynamic>{
          'nutrient_recommendations': <dynamic>[],
        }),
        e2a: E2aGoalCalculator(const <String, dynamic>{
          'user_goal_mappings': <dynamic>[],
        }),
        e2b: E2bAgeCalculator(const <String, dynamic>{
          'nutrient_recommendations': <dynamic>[],
        }),
      );

      final result = service.calculate(
        nutrients: const <Map<String, dynamic>>[],
        productClusters: const <String>[],
        interactionSummary: const <String, dynamic>{},
      );

      expect(result.missingFields, contains('age'));
      expect(result.missingFields, contains('sex'));
      expect(result.missingFields, contains('goals'));
    });

    test('explicit no-goals choice is not scored or treated as missing', () {
      final service = FitScoreService(
        e1: E1DosageCalculator(const <String, dynamic>{
          'nutrient_recommendations': <dynamic>[],
        }),
        e2a: E2aGoalCalculator(const <String, dynamic>{
          'user_goal_mappings': <dynamic>[],
        }),
        e2b: E2bAgeCalculator(const <String, dynamic>{
          'nutrient_recommendations': <dynamic>[],
        }),
      );

      final result = service.calculate(
        nutrients: const <Map<String, dynamic>>[],
        productClusters: const <String>[],
        productGoalMatches: const <String>['GOAL_SLEEP_QUALITY'],
        interactionSummary: const <String, dynamic>{},
        ageBracket: '19-30',
        sex: 'Female',
        userGoals: const <String>[SchemaIds.goalNone],
      );

      expect(result.missingFields, isNot(contains('goals')));
      expect(
        result.reasons,
        isNot(contains('Does not strongly support your selected goals.')),
      );
    });

    test('prefers pipeline goal matches over local cluster fallback', () {
      final service = FitScoreService(
        e1: E1DosageCalculator({'nutrient_recommendations': <Object>[]}),
        e2a: E2aGoalCalculator({
          'user_goal_mappings': [
            {
              'id': 'GOAL_SLEEP_QUALITY',
              'cluster_weights': {'sleep_stack': 1.0},
              'anti_clusters': <Object>[],
            },
          ],
        }),
        e2b: E2bAgeCalculator({'nutrient_recommendations': <Object>[]}),
      );

      final result = service.calculate(
        nutrients: const [],
        productClusters: const [],
        productGoalMatches: const ['GOAL_SLEEP_QUALITY'],
        productGoalMatchConfidence: 0.8,
        interactionSummary: const {},
        ageBracket: '19-30',
        sex: 'Female',
        userGoals: const ['GOAL_SLEEP_QUALITY'],
      );

      expect(result.state, FitAssessmentState.strongMatch);
      expect(result.reasons, contains('Supports your Sleep Quality goal.'));
    });

    test('limits fit when selected goals are not matched', () {
      final service = FitScoreService(
        e1: E1DosageCalculator({'nutrient_recommendations': <Object>[]}),
        e2a: E2aGoalCalculator({'user_goal_mappings': <Object>[]}),
        e2b: E2bAgeCalculator({'nutrient_recommendations': <Object>[]}),
      );

      final result = service.calculate(
        nutrients: const [],
        productClusters: const [],
        interactionSummary: const {},
        ageBracket: '19-30',
        sex: 'Female',
        userGoals: const ['GOAL_SLEEP_QUALITY'],
      );

      expect(result.state, FitAssessmentState.limitedFit);
      expect(
        result.reasons,
        contains('Does not strongly support your selected goals.'),
      );
    });

    test(
      'validated cluster fallback can earn Good fit, never Strong match',
      () {
        final service = FitScoreService(
          e1: E1DosageCalculator({'nutrient_recommendations': <Object>[]}),
          e2a: E2aGoalCalculator({
            'user_goal_mappings': [
              {
                'id': 'GOAL_SLEEP_QUALITY',
                'cluster_weights': {'sleep_stack': 1.0},
                'required_clusters': ['sleep_stack'],
                'blocked_by_clusters': <Object>[],
                'min_match_score': 0.5,
              },
            ],
          }),
          e2b: E2bAgeCalculator({'nutrient_recommendations': <Object>[]}),
        );

        final result = service.calculate(
          nutrients: const [],
          productClusters: const ['sleep_stack'],
          interactionSummary: const {},
          ageBracket: '19-30',
          sex: 'Female',
          userGoals: const ['GOAL_SLEEP_QUALITY'],
        );

        expect(result.state, FitAssessmentState.goodFit);
        expect(
          result.reasons,
          contains('Its ingredient profile aligns with your selected goals.'),
        );
      },
    );

    FitScoreService buildBareService() => FitScoreService(
      e1: E1DosageCalculator({'nutrient_recommendations': <Object>[]}),
      e2a: E2aGoalCalculator({'user_goal_mappings': <Object>[]}),
      e2b: E2bAgeCalculator({'nutrient_recommendations': <Object>[]}),
    );

    test('tolerates untyped condition/drug summaries (jsonDecode shape) '
        'without throwing', () {
      final service = buildBareService();

      // Map<dynamic, dynamic> values — the shape a hard
      // `as Map<String, dynamic>?` cast would reject with a TypeError.
      final summary = <String, dynamic>{
        'condition_summary': <dynamic, dynamic>{
          'hypertension': <dynamic, dynamic>{
            'label': 'High blood pressure',
            'highest_severity': 'avoid',
            'ingredients': <dynamic>['licorice'],
          },
        },
        'drug_class_summary': <dynamic, dynamic>{},
      };

      final result = service.calculate(
        nutrients: const [],
        productClusters: const [],
        interactionSummary: summary,
        ageBracket: '19-30',
        sex: 'Female',
        userConditions: const ['hypertension'],
      );

      expect(result.maxRelevantSeverity, 'avoid');
    });

    test('malformed summaries (non-map values) degrade to no matches', () {
      final service = buildBareService();

      final result = service.calculate(
        nutrients: const [],
        productClusters: const [],
        interactionSummary: const <String, dynamic>{
          'condition_summary': 'drifted-to-string',
          'drug_class_summary': 42,
        },
        ageBracket: '19-30',
        sex: 'Female',
        userConditions: const ['hypertension'],
      );

      expect(result.maxRelevantSeverity, isNull);
      expect(result.state, isNot(FitAssessmentState.notRecommended));
    });
  });
}
