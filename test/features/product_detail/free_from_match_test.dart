import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/free_from_match.dart';

void main() {
  group('matchFreeFromClaims — empty inputs', () {
    test('empty user allergens → empty list', () {
      final claims = matchFreeFromClaims(
        userAllergenIds: const {},
        isGlutenFree: 1,
        isDairyFree: 1,
        isSoyFree: 1,
      );
      expect(claims, isEmpty);
    });

    test('user has only unmapped allergen (eggs) → empty list', () {
      final claims = matchFreeFromClaims(
        userAllergenIds: const {'ALLERGEN_EGGS'},
        isGlutenFree: 1,
        isDairyFree: 1,
        isSoyFree: 1,
      );
      expect(claims, isEmpty);
    });
  });

  group('matchFreeFromClaims — gluten', () {
    test('user has wheat + product is gluten-free → certified', () {
      final claims = matchFreeFromClaims(
        userAllergenIds: const {'ALLERGEN_WHEAT'},
        isGlutenFree: 1,
        isDairyFree: null,
        isSoyFree: null,
      );
      expect(claims.length, 1);
      expect(claims.single.concern, 'gluten');
      expect(claims.single.label, 'Gluten-free');
      expect(claims.single.status, FreeFromStatus.certified);
    });

    test('user has barley alone → still triggers gluten concern', () {
      final claims = matchFreeFromClaims(
        userAllergenIds: const {'ALLERGEN_BARLEY'},
        isGlutenFree: 1,
        isDairyFree: null,
        isSoyFree: null,
      );
      expect(claims.length, 1);
      expect(claims.single.concern, 'gluten');
    });

    test('user has gluten + flag null → unknown', () {
      final claims = matchFreeFromClaims(
        userAllergenIds: const {'ALLERGEN_WHEAT'},
        isGlutenFree: null,
        isDairyFree: null,
        isSoyFree: null,
      );
      expect(claims.single.status, FreeFromStatus.unknown);
    });

    test('user has gluten + flag 0 → notClaimed', () {
      final claims = matchFreeFromClaims(
        userAllergenIds: const {'ALLERGEN_WHEAT'},
        isGlutenFree: 0,
        isDairyFree: null,
        isSoyFree: null,
      );
      expect(claims.single.status, FreeFromStatus.notClaimed);
    });

    test('all four grain IDs collapse to a single gluten claim (no dupes)', () {
      final claims = matchFreeFromClaims(
        userAllergenIds: const {
          'ALLERGEN_WHEAT',
          'ALLERGEN_BARLEY',
          'ALLERGEN_RYE',
          'ALLERGEN_OATS',
        },
        isGlutenFree: 1,
        isDairyFree: null,
        isSoyFree: null,
      );
      expect(claims.length, 1, reason: 'gluten concern emits exactly once');
    });
  });

  group('matchFreeFromClaims — multi-concern', () {
    test('user has all three concerns → three claims in order', () {
      final claims = matchFreeFromClaims(
        userAllergenIds: const {
          'ALLERGEN_WHEAT',
          'ALLERGEN_MILK',
          'ALLERGEN_SOY',
        },
        isGlutenFree: 1,
        isDairyFree: null,
        isSoyFree: 0,
      );
      expect(claims.length, 3);
      expect(claims[0].concern, 'gluten');
      expect(claims[0].status, FreeFromStatus.certified);
      expect(claims[1].concern, 'dairy');
      expect(claims[1].status, FreeFromStatus.unknown);
      expect(claims[2].concern, 'soy');
      expect(claims[2].status, FreeFromStatus.notClaimed);
    });

    test('user has dairy + soy only → no gluten claim', () {
      final claims = matchFreeFromClaims(
        userAllergenIds: const {'ALLERGEN_MILK', 'ALLERGEN_SOY'},
        isGlutenFree: 1,
        isDairyFree: 1,
        isSoyFree: 1,
      );
      expect(claims.map((c) => c.concern).toList(), ['dairy', 'soy']);
    });
  });

  group('FreeFromClaim equality', () {
    test('same fields → equal', () {
      const a = FreeFromClaim(
        label: 'Gluten-free',
        concern: 'gluten',
        status: FreeFromStatus.certified,
      );
      const b = FreeFromClaim(
        label: 'Gluten-free',
        concern: 'gluten',
        status: FreeFromStatus.certified,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different status → not equal', () {
      const a = FreeFromClaim(
        label: 'Gluten-free',
        concern: 'gluten',
        status: FreeFromStatus.certified,
      );
      const b = FreeFromClaim(
        label: 'Gluten-free',
        concern: 'gluten',
        status: FreeFromStatus.unknown,
      );
      expect(a, isNot(b));
    });
  });

  group('findFreeFromConflicts', () {
    test('no contains matches → no conflicts even with claims', () {
      final conflicts = findFreeFromConflicts(
        matchedContainsAllergenIds: const {},
        isGlutenFree: 1,
        isDairyFree: 1,
        isSoyFree: 1,
      );
      expect(conflicts, isEmpty);
    });

    test('wheat contains + isGlutenFree=1 → gluten conflict', () {
      final conflicts = findFreeFromConflicts(
        matchedContainsAllergenIds: const {'ALLERGEN_WHEAT'},
        isGlutenFree: 1,
        isDairyFree: null,
        isSoyFree: null,
      );
      expect(conflicts, ['gluten']);
    });

    test('barley contains + isGlutenFree=1 → gluten conflict', () {
      final conflicts = findFreeFromConflicts(
        matchedContainsAllergenIds: const {'ALLERGEN_BARLEY'},
        isGlutenFree: 1,
        isDairyFree: null,
        isSoyFree: null,
      );
      expect(conflicts, ['gluten']);
    });

    test('milk contains + isDairyFree=1 → dairy conflict', () {
      final conflicts = findFreeFromConflicts(
        matchedContainsAllergenIds: const {'ALLERGEN_MILK'},
        isGlutenFree: null,
        isDairyFree: 1,
        isSoyFree: null,
      );
      expect(conflicts, ['dairy']);
    });

    test('soy contains + isSoyFree=1 → soy conflict', () {
      final conflicts = findFreeFromConflicts(
        matchedContainsAllergenIds: const {'ALLERGEN_SOY'},
        isGlutenFree: null,
        isDairyFree: null,
        isSoyFree: 1,
      );
      expect(conflicts, ['soy']);
    });

    test('wheat contains + isGlutenFree=null → no conflict (just unknown)', () {
      final conflicts = findFreeFromConflicts(
        matchedContainsAllergenIds: const {'ALLERGEN_WHEAT'},
        isGlutenFree: null,
        isDairyFree: null,
        isSoyFree: null,
      );
      expect(conflicts, isEmpty);
    });

    test('wheat contains + isGlutenFree=0 → no conflict (consistent)', () {
      final conflicts = findFreeFromConflicts(
        matchedContainsAllergenIds: const {'ALLERGEN_WHEAT'},
        isGlutenFree: 0,
        isDairyFree: null,
        isSoyFree: null,
      );
      expect(conflicts, isEmpty);
    });

    test('all three concerns conflict at once → all three returned', () {
      final conflicts = findFreeFromConflicts(
        matchedContainsAllergenIds: const {
          'ALLERGEN_WHEAT',
          'ALLERGEN_MILK',
          'ALLERGEN_SOY',
        },
        isGlutenFree: 1,
        isDairyFree: 1,
        isSoyFree: 1,
      );
      expect(conflicts, ['gluten', 'dairy', 'soy']);
    });
  });
}
