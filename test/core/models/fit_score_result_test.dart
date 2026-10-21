import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';

void main() {
  group('FitScoreResult', () {
    test('displayText with complete profile', () {
      const result = FitScoreResult(
        missingFields: [],
        state: FitAssessmentState.strongMatch,
        mappedCoverage: 1.0,
      );
      expect(result.displayText, 'Strong match');
    });

    test('displayText with missing fields', () {
      const result = FitScoreResult(
        missingFields: ['goals', 'conditions'],
        state: FitAssessmentState.incompleteProfile,
        mappedCoverage: 1.0,
      );
      expect(result.displayText, 'Incomplete profile — Complete profile');
    });
  });
}
