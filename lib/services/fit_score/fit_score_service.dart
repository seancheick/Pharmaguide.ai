import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2c_medical_calculator.dart';

class FitScoreService {
  final E1DosageCalculator e1;
  final E2aGoalCalculator e2a;
  final E2bAgeCalculator e2b;
  final E2cMedicalCalculator e2c;

  FitScoreService({
    required this.e1,
    required this.e2a,
    required this.e2b,
    required this.e2c,
  });

  FitScoreResult calculate({
    required double scoreQuality80,
    required List<Map<String, dynamic>> nutrients,
    required List<String> productClusters,
    required Map<String, dynamic> interactionSummary,
    String? ageBracket,
    String? sex,
    List<String> userGoals = const [],
    List<String> userConditions = const [],
    List<String> userDrugClasses = const [],
  }) {
    final e1Score = e1.calculate(
      nutrients: nutrients,
      ageBracket: ageBracket,
      sex: sex,
    );
    final e2aScore = e2a.calculate(
      productClusters: productClusters,
      userGoals: userGoals,
    );
    final e2bScore = e2b.calculate(
      nutrients: nutrients,
      ageBracket: ageBracket,
    );
    final e2cScore = e2c.calculate(
      interactionSummary: interactionSummary,
      userConditions: userConditions,
      userDrugClasses: userDrugClasses,
    );

    final scoreFit20 = e1Score + e2aScore + e2bScore + e2cScore;
    final scoreCombined100 = (scoreQuality80 + scoreFit20) * 100 / 100;

    final missingFields = <String>[];
    if (ageBracket == null) missingFields.add('age');
    if (sex == null) missingFields.add('sex');
    if (userGoals.isEmpty) missingFields.add('goals');

    final maxPossible = _maxPossible(ageBracket, sex, userGoals, userConditions);

    return FitScoreResult(
      scoreFit20: scoreFit20,
      scoreCombined100: scoreCombined100,
      e1: e1Score,
      e2a: e2aScore,
      e2b: e2bScore,
      e2c: e2cScore,
      missingFields: missingFields,
      maxPossible: maxPossible,
    );
  }

  double _maxPossible(
    String? ageBracket,
    String? sex,
    List<String> goals,
    List<String> conditions,
  ) {
    double max = 80.0; // Base quality
    max += 7.0; // E1 always available (even in degraded mode)
    if (goals.isNotEmpty) max += 2.0; // E2a
    if (ageBracket != null) max += 3.0; // E2b
    max += 8.0; // E2c always runs (no conditions = full points)
    return max;
  }
}
