import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';

void main() {
  group('FitScoreResult', () {
    test('displayText with complete profile', () {
      final result = FitScoreResult(
        scoreFit20: 15.0,
        scoreCombined100: 85.0,
        e1: 5.0,
        e2a: 2.0,
        e2b: 3.0,
        e2c: 5.0,
        missingFields: [],
        maxPossible: 100.0,
      );
      expect(result.displayText, '85/100 (85.0%)');
    });

    test('displayText with missing fields', () {
      final result = FitScoreResult(
        scoreFit20: 8.0,
        scoreCombined100: 73.0,
        e1: 5.0,
        e2a: 0.0,
        e2b: 3.0,
        e2c: 0.0,
        missingFields: ['goals', 'conditions'],
        maxPossible: 90.0,
      );
      expect(result.displayText, contains('Complete profile for full scoring'));
    });
  });
}
