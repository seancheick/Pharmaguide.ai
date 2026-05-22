// Safety invariant: a "safe"/"good fit" verdict is never returned when
// mapped_coverage < 0.3.
//
// PharmaGuide's verdict UI is downstream of FitScoreService.calculate().
// When the ingredient mapping is below the 0.3 confidence floor, the
// service must short-circuit to FitAssessmentState.limitedFit — never
// goodFit or strongMatch. The label confidence layer enforces the same
// rule independently (LabelConfidenceTier.limited). If either path
// returns an optimistic state under low coverage, the user can see
// "Safe" / "Good fit" on a product the app doesn't actually understand,
// which is the canonical medical-safety failure mode this app exists to
// prevent.
//
// The 0.3 threshold is the source of truth in
// lib/services/fit_score/fit_score_service.dart:287. If a regression
// moves the threshold or removes the branch, this test fails first.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2c_medical_calculator.dart';
import 'package:pharmaguide/services/fit_score/fit_score_service.dart';

FitScoreService _buildService() {
  return FitScoreService(
    e1: E1DosageCalculator(const <String, dynamic>{
      'nutrient_recommendations': <dynamic>[],
    }),
    e2a: E2aGoalCalculator(const <String, dynamic>{
      'user_goal_mappings': <dynamic>[],
    }),
    e2b: E2bAgeCalculator(const <String, dynamic>{
      'nutrient_recommendations': <dynamic>[],
    }),
    e2c: E2cMedicalCalculator(),
  );
}

FitScoreResult _calculate({required double mappedCoverage}) {
  // Profile is intentionally complete (age, sex, goals) so the
  // calculate() function bypasses the `incompleteProfile` early-return
  // and we actually exercise the mappedCoverage branch.
  return _buildService().calculate(
    nutrients: const <Map<String, dynamic>>[],
    productClusters: const <String>[],
    interactionSummary: const <String, dynamic>{},
    ageBracket: '19-30',
    sex: 'Male',
    userGoals: const ['GOAL_SLEEP_QUALITY'],
    mappedCoverage: mappedCoverage,
  );
}

void main() {
  group('Safety invariant: low coverage is never a positive verdict', () {
    test('mappedCoverage = 0.0 returns limitedFit', () {
      final result = _calculate(mappedCoverage: 0.0);
      expect(result.state, FitAssessmentState.limitedFit);
      expect(result.state, isNot(FitAssessmentState.goodFit));
      expect(result.state, isNot(FitAssessmentState.strongMatch));
    });

    test('mappedCoverage just below threshold (0.29) returns limitedFit', () {
      final result = _calculate(mappedCoverage: 0.29);
      expect(result.state, FitAssessmentState.limitedFit);
    });

    test('mappedCoverage = 0.15 returns limitedFit', () {
      final result = _calculate(mappedCoverage: 0.15);
      expect(result.state, FitAssessmentState.limitedFit);
    });

    test('mappedCoverage at threshold (0.3) does NOT trigger the floor', () {
      // 0.3 is the boundary — the rule is strict `<`, so 0.3 itself
      // should not force limitedFit. This locks the boundary so a
      // refactor can't silently flip `<` to `<=` (which would
      // over-restrict) or to `< 0.5` (which would under-restrict).
      final result = _calculate(mappedCoverage: 0.3);
      final reasonsText = result.reasons.join(' ').toLowerCase();
      expect(
        reasonsText.contains('ingredient mapping coverage is low'),
        isFalse,
        reason:
            'At mappedCoverage = 0.3 (boundary), the low-coverage branch '
            'must not fire. The threshold is strictly `<`.',
      );
    });

    test('mappedCoverage = 1.0 (full coverage) does not force limitedFit', () {
      final result = _calculate(mappedCoverage: 1.0);
      final reasonsText = result.reasons.join(' ').toLowerCase();
      expect(
        reasonsText.contains('ingredient mapping coverage is low'),
        isFalse,
      );
    });

    test('low coverage propagates mappedCoverage into the result', () {
      // Downstream UI reads result.mappedCoverage to decide LabelConfidence.
      // If this value is lost, the UI can't enforce the parallel rule.
      final result = _calculate(mappedCoverage: 0.1);
      expect(result.mappedCoverage, 0.1);
    });
  });
}
