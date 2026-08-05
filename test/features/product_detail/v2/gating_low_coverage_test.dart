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
}
