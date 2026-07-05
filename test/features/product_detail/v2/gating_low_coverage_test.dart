// FIX 2 (P1) — gating.dart previously had no low-coverage gate at all:
// `productIsNotScored` only catches a null score, so a scored product with
// mapped_coverage < 0.3 sailed straight into the confident tier-colored
// hero score line. `productHasLowCoverage` is the product-row-level gate
// the hero adapter (sections/hero_section.dart) threads into PGHeroSection.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/features/product_detail/v2/gating.dart';

ProductsCoreData _row({double? mappedCoverage}) {
  return ProductsCoreData(
    dsldId: 'TEST-1',
    productName: 'Test Supplement',
    mappedCoverage: mappedCoverage,
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
}
