// FIX 2 (P1) — gating.dart previously had no low-coverage gate at all:
// `productIsNotScored` only catches a null score, so a scored product with
// mapped_coverage < 0.3 sailed straight into the confident tier-colored
// hero score line. `productHasLowCoverage` is the product-row-level gate
// the hero adapter (sections/hero_section.dart) threads into PGHeroSection.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/features/product_detail/v2/gating.dart';

ProductsCoreData _row({
  double? mappedCoverage,
  double? qualityScore = 82,
  String? verdict,
  String? productSafetyStatus,
  String? qualityScoreStatus,
  String? qualityAssessmentStatus,
}) {
  return ProductsCoreData(
    dsldId: 'TEST-1',
    productName: 'Test Supplement',
    mappedCoverage: mappedCoverage,
    qualityScoreV4100: qualityScore,
    verdict: verdict,
    productSafetyStatus: productSafetyStatus,
    qualityScoreStatus: qualityScoreStatus,
    qualityAssessmentStatus: qualityAssessmentStatus,
    exportVersion: 'test',
    exportedAt: '2026-07-05T00:00:00Z',
  );
}

void main() {
  group('productHasLowCoverage', () {
    test('coverage below the 0.3 floor is low', () {
      expect(productHasLowCoverage(_row(mappedCoverage: 0.2)), isTrue);
    });

    test('null coverage is low (unknown ≠ trustworthy)', () {
      expect(productHasLowCoverage(_row(mappedCoverage: null)), isTrue);
    });

    test('null product is low (nothing to trust)', () {
      expect(productHasLowCoverage(null), isTrue);
    });

    test('coverage at the floor is trusted (floor is `< 0.3`)', () {
      expect(productHasLowCoverage(_row(mappedCoverage: 0.3)), isFalse);
    });

    test('healthy coverage is trusted', () {
      expect(productHasLowCoverage(_row(mappedCoverage: 0.9)), isFalse);
    });
  });

  group('independent consumer semantics', () {
    test(
      'catalog safety status blocks independently of a POOR quality verdict',
      () {
        final product = _row(
          verdict: 'POOR',
          productSafetyStatus: 'blocked',
          qualityScoreStatus: 'suppressed_safety',
          qualityAssessmentStatus: 'complete',
        );

        expect(productIsBlocked(product), isTrue);
        expect(productIsNotScored(product), isFalse);
      },
    );

    test('POOR quality does not become a catalog safety block', () {
      final product = _row(
        verdict: 'POOR',
        productSafetyStatus: 'no_known_catalog_concern',
        qualityScoreStatus: 'scored',
        qualityAssessmentStatus: 'complete',
      );

      expect(productIsBlocked(product), isFalse);
      expect(productIsNotScored(product), isFalse);
    });

    test(
      'failed quality assessment does not depend on legacy verdict or score',
      () {
        final product = _row(
          verdict: 'SAFE',
          productSafetyStatus: 'no_known_catalog_concern',
          qualityScoreStatus: 'not_scored',
          qualityAssessmentStatus: 'failed',
        );

        expect(productIsNotScored(product), isTrue);
      },
    );

    test('old catalog falls back to the legacy verdict', () {
      final product = _row(verdict: 'BLOCKED', qualityScore: null);

      expect(productIsBlocked(product), isTrue);
      expect(productIsNotScored(product), isFalse);
    });

    test('old POOR verdict remains quality-only', () {
      final product = _row(verdict: 'POOR', qualityScore: 39);

      expect(productIsBlocked(product), isFalse);
      expect(productIsNotScored(product), isFalse);
    });

    test('unknown populated v2.2 states fail closed instead of using SAFE', () {
      final product = _row(
        verdict: 'SAFE',
        productSafetyStatus: 'future_safety_state',
        qualityAssessmentStatus: 'future_assessment_state',
      );

      expect(
        catalogProductSafetyStatus(product),
        CatalogProductSafetyStatus.notAssessed,
      );
      expect(catalogAssessmentStatus(product), CatalogAssessmentStatus.failed);
      expect(productIsNotScored(product), isTrue);
    });
  });

  group('catalog compatibility matrix', () {
    test('new safety status is authoritative over every legacy verdict', () {
      final cases =
          <
            ({
              String newStatus,
              String legacyVerdict,
              CatalogProductSafetyStatus expected,
            })
          >[
            (
              newStatus: 'blocked',
              legacyVerdict: 'SAFE',
              expected: CatalogProductSafetyStatus.blocked,
            ),
            (
              newStatus: 'unsafe',
              legacyVerdict: 'SAFE',
              expected: CatalogProductSafetyStatus.unsafe,
            ),
            (
              newStatus: 'caution',
              legacyVerdict: 'SAFE',
              expected: CatalogProductSafetyStatus.caution,
            ),
            (
              newStatus: 'no_known_catalog_concern',
              legacyVerdict: 'BLOCKED',
              expected: CatalogProductSafetyStatus.noKnownCatalogConcern,
            ),
            (
              newStatus: 'not_assessed',
              legacyVerdict: 'SAFE',
              expected: CatalogProductSafetyStatus.notAssessed,
            ),
            (
              newStatus: 'future_state',
              legacyVerdict: 'SAFE',
              expected: CatalogProductSafetyStatus.notAssessed,
            ),
          ];

      for (final testCase in cases) {
        final product = _row(
          verdict: testCase.legacyVerdict,
          productSafetyStatus: testCase.newStatus,
        );
        expect(
          catalogProductSafetyStatus(product),
          testCase.expected,
          reason: 'new=${testCase.newStatus}, legacy=${testCase.legacyVerdict}',
        );
      }
    });

    test('legacy safety fallback preserves historical meanings', () {
      final cases = <(String, CatalogProductSafetyStatus)>[
        ('BLOCKED', CatalogProductSafetyStatus.blocked),
        ('UNSAFE', CatalogProductSafetyStatus.unsafe),
        ('CAUTION', CatalogProductSafetyStatus.caution),
        ('SAFE', CatalogProductSafetyStatus.noKnownCatalogConcern),
        ('POOR', CatalogProductSafetyStatus.noKnownCatalogConcern),
        ('NOT_SCORED', CatalogProductSafetyStatus.notAssessed),
      ];

      for (final (verdict, expected) in cases) {
        expect(
          catalogProductSafetyStatus(_row(verdict: verdict)),
          expected,
          reason: 'legacy verdict=$verdict',
        );
      }
    });

    test('new quality contradictions fail closed', () {
      final cases =
          <
            ({
              String? scoreStatus,
              String? assessmentStatus,
              double? score,
              bool expectedNotScored,
            })
          >[
            (
              scoreStatus: 'scored',
              assessmentStatus: 'failed',
              score: 82,
              expectedNotScored: true,
            ),
            (
              scoreStatus: 'scored',
              assessmentStatus: 'partial',
              score: 82,
              expectedNotScored: true,
            ),
            (
              scoreStatus: 'future_state',
              assessmentStatus: 'complete',
              score: 82,
              expectedNotScored: true,
            ),
            (
              scoreStatus: 'scored',
              assessmentStatus: 'complete',
              score: null,
              expectedNotScored: true,
            ),
            (
              scoreStatus: 'not_scored',
              assessmentStatus: 'complete',
              score: 82,
              expectedNotScored: true,
            ),
            (
              scoreStatus: 'suppressed_safety',
              assessmentStatus: 'complete',
              score: null,
              expectedNotScored: false,
            ),
          ];

      for (final testCase in cases) {
        final product = _row(
          qualityScoreStatus: testCase.scoreStatus,
          qualityAssessmentStatus: testCase.assessmentStatus,
          qualityScore: testCase.score,
        );
        expect(
          catalogProductIsNotScored(product),
          testCase.expectedNotScored,
          reason:
              'score_status=${testCase.scoreStatus}, '
              'assessment=${testCase.assessmentStatus}, '
              'score=${testCase.score}',
        );
      }
    });

    test('legacy quality fallback stays additive-schema compatible', () {
      final cases = <({String verdict, double? score, bool expectedNotScored})>[
        (verdict: 'NOT_SCORED', score: null, expectedNotScored: true),
        (verdict: 'SAFE', score: null, expectedNotScored: true),
        (verdict: 'SAFE', score: 82, expectedNotScored: false),
        (verdict: 'POOR', score: 39, expectedNotScored: false),
        (verdict: 'BLOCKED', score: null, expectedNotScored: false),
        (verdict: 'UNSAFE', score: null, expectedNotScored: false),
      ];

      for (final testCase in cases) {
        expect(
          catalogProductIsNotScored(
            _row(verdict: testCase.verdict, qualityScore: testCase.score),
          ),
          testCase.expectedNotScored,
          reason: 'legacy verdict=${testCase.verdict}, score=${testCase.score}',
        );
      }
    });
  });
}
