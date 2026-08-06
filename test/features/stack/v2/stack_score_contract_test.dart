import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/features/stack/v2/stack_v2_screen.dart';

ProductsCoreData _product({
  double? score = 82,
  double? coverage = 0.9,
  String? productSafetyStatus = 'no_known_catalog_concern',
  String? assessmentStatus = 'complete',
  String? scoreStatus = 'scored',
  String? confidence = 'moderate',
  String? qualityTier = 'Strong',
  String? verdict,
}) {
  return ProductsCoreData(
    dsldId: 'stack-score-test',
    productName: 'Test Supplement',
    qualityScoreV4100: score,
    mappedCoverage: coverage,
    productSafetyStatus: productSafetyStatus,
    qualityAssessmentStatus: assessmentStatus,
    qualityScoreStatus: scoreStatus,
    v4Confidence: confidence,
    qualityTier: qualityTier,
    verdict: verdict,
    exportVersion: 'test',
    exportedAt: '2026-08-05T00:00:00Z',
  );
}

void main() {
  group('stackCatalogScoreDisplayFor', () {
    test('returns the current catalog score and confidence', () {
      expect(stackCatalogScoreDisplayFor(_product()), (
        score: 82,
        qualityTier: 'Strong',
        confidence: 'moderate',
      ));
    });

    test('suppresses a blocked product even if a score leaked through', () {
      expect(
        stackCatalogScoreDisplayFor(_product(productSafetyStatus: 'blocked')),
        isNull,
      );
    });

    test('suppresses a failed assessment even if status says scored', () {
      expect(
        stackCatalogScoreDisplayFor(_product(assessmentStatus: 'failed')),
        isNull,
      );
    });

    test('suppresses an unknown score status', () {
      expect(
        stackCatalogScoreDisplayFor(_product(scoreStatus: 'future_status')),
        isNull,
      );
    });

    test('suppresses low or unknown coverage', () {
      expect(stackCatalogScoreDisplayFor(_product(coverage: 0.2)), isNull);
      expect(stackCatalogScoreDisplayFor(_product(coverage: null)), isNull);
    });

    test('preserves the old-catalog compatibility path', () {
      expect(
        stackCatalogScoreDisplayFor(
          _product(
            productSafetyStatus: null,
            assessmentStatus: null,
            scoreStatus: null,
            confidence: null,
            verdict: 'SAFE',
          ),
        ),
        (score: 82, qualityTier: 'Strong', confidence: null),
      );
    });

    test('does not reuse a saved score while the product is unavailable', () {
      expect(stackCatalogScoreDisplayFor(null), isNull);
    });
  });
}
