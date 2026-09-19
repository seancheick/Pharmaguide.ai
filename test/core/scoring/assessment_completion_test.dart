// A number can exist without the assessment behind it being complete.
//
// `quality_score_status` and `quality_assessment_status` answer different
// questions. Collapsing them was the root defect: 4,117 catalog products whose
// Evidence pillar was never reviewed published a definitive tier anyway, and
// the app told users "not enough verified data to score" — blaming the label
// for a review PharmaGuide had not performed.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_hero_section.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/data/database/core_database.dart';

ProductsCoreData _p({
  String? qualityScoreStatus,
  String? qualityAssessmentStatus,
  double? qualityScoreV4100,
  String? productSafetyStatus = 'no_known_catalog_concern',
}) => ProductsCoreData(
  dsldId: 'TEST-1',
  productName: 'Test Supplement',
  mappedCoverage: 1.0,
  qualityScoreV4100: qualityScoreV4100,
  productSafetyStatus: productSafetyStatus,
  qualityScoreStatus: qualityScoreStatus,
  qualityAssessmentStatus: qualityAssessmentStatus,
  exportVersion: 'test',
  exportedAt: '2026-09-19T00:00:00Z',
);

void main() {
  group('scored + partial is its own state', () {
    final partial = _p(
      qualityScoreStatus: 'scored',
      qualityAssessmentStatus: 'partial',
      qualityScoreV4100: 54,
    );

    test('is NOT not-scored — the five assessed pillars must still render', () {
      expect(catalogProductIsNotScored(partial), isFalse);
    });

    test('is reported as an incomplete assessment', () {
      expect(catalogProductAssessmentIncomplete(partial), isTrue);
    });

    test('has no completed public score', () {
      expect(catalogProductHasCompletePublicScore(partial), isFalse);
    });

    test('hero withholds the tier without claiming there is no analysis', () {
      expect(
        heroScoreDisplayFor(
          score: 54,
          isBlocked: false,
          isNotScored: false,
          lowCoverage: false,
          assessmentIncomplete: true,
        ),
        HeroScoreDisplay.assessmentIncomplete,
      );
    });
  });

  group('scored + complete is unaffected', () {
    final complete = _p(
      qualityScoreStatus: 'scored',
      qualityAssessmentStatus: 'complete',
      qualityScoreV4100: 61,
    );

    test('renders a normal completed verdict', () {
      expect(catalogProductIsNotScored(complete), isFalse);
      expect(catalogProductAssessmentIncomplete(complete), isFalse);
      expect(catalogProductHasCompletePublicScore(complete), isTrue);
      expect(
        heroScoreDisplayFor(
          score: 61,
          isBlocked: false,
          isNotScored: false,
          lowCoverage: false,
          assessmentIncomplete: false,
        ),
        HeroScoreDisplay.tierScore,
      );
    });
  });

  group('genuinely unscored and failed stay unscored', () {
    test('not_scored + partial has no usable number', () {
      final p = _p(
        qualityScoreStatus: 'not_scored',
        qualityAssessmentStatus: 'partial',
      );
      expect(catalogProductIsNotScored(p), isTrue);
      // Already not-scored; not additionally reported as "incomplete".
      expect(catalogProductAssessmentIncomplete(p), isFalse);
      expect(catalogProductHasCompletePublicScore(p), isFalse);
    });

    test('failed assessment yields nothing trustworthy', () {
      final p = _p(
        qualityScoreStatus: 'scored',
        qualityAssessmentStatus: 'failed',
        qualityScoreV4100: 70,
      );
      expect(catalogProductIsNotScored(p), isTrue);
      expect(catalogProductHasCompletePublicScore(p), isFalse);
    });

    test('scored status with a null number is still unscored', () {
      final p = _p(
        qualityScoreStatus: 'scored',
        qualityAssessmentStatus: 'complete',
      );
      expect(catalogProductIsNotScored(p), isTrue);
    });
  });

  group('older catalogs keep working', () {
    test('a row with no assessment status falls back to score status', () {
      final p = _p(qualityScoreStatus: 'scored', qualityScoreV4100: 80);
      expect(catalogProductIsNotScored(p), isFalse);
      expect(catalogProductAssessmentIncomplete(p), isFalse);
      expect(catalogProductHasCompletePublicScore(p), isTrue);
    });

    test('a blocked product never has a completed public score', () {
      final p = _p(
        qualityScoreStatus: 'scored',
        qualityAssessmentStatus: 'complete',
        qualityScoreV4100: 90,
        productSafetyStatus: 'blocked',
      );
      expect(catalogProductHasCompletePublicScore(p), isFalse);
    });
  });
}
