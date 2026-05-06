import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';

void main() {
  group('ProfileState.migrateLegacyAllergenIds', () {
    test('renames legacy singular IDs to canonical plural', () {
      final out = ProfileState.migrateLegacyAllergenIds(const [
        'ALLERGEN_EGG',
        'ALLERGEN_PEANUT',
        'ALLERGEN_SULFITE',
      ]);
      expect(out.toSet(), {
        'ALLERGEN_EGGS',
        'ALLERGEN_PEANUTS',
        'ALLERGEN_SULFITES',
      });
    });

    test('expands ALLERGEN_SHELLFISH to crustaceans + molluscs', () {
      final out = ProfileState.migrateLegacyAllergenIds(const [
        'ALLERGEN_SHELLFISH',
      ]);
      expect(out.toSet(), {'ALLERGEN_CRUSTACEANS', 'ALLERGEN_MOLLUSCS'});
    });

    test('expands ALLERGEN_GLUTEN to wheat + barley + rye + oats', () {
      final out = ProfileState.migrateLegacyAllergenIds(const [
        'ALLERGEN_GLUTEN',
      ]);
      expect(out.toSet(), {
        'ALLERGEN_WHEAT',
        'ALLERGEN_BARLEY',
        'ALLERGEN_RYE',
        'ALLERGEN_OATS',
      });
    });

    test('drops unsupported sensitivity IDs silently', () {
      final out = ProfileState.migrateLegacyAllergenIds(const [
        'ALLERGEN_MILK', // canonical — kept
        'ALLERGEN_CORN', // unsupported — dropped
        'ALLERGEN_YEAST',
        'ALLERGEN_GELATIN',
        'ALLERGEN_LATEX_FRUIT',
        'ALLERGEN_NIGHTSHADE',
        'ALLERGEN_SALICYLATE',
      ]);
      expect(out, ['ALLERGEN_MILK']);
    });

    test('canonical IDs pass through untouched (idempotent)', () {
      const canonical = [
        'ALLERGEN_MILK',
        'ALLERGEN_EGGS',
        'ALLERGEN_FISH',
        'ALLERGEN_CRUSTACEANS',
        'ALLERGEN_MOLLUSCS',
        'ALLERGEN_TREE_NUTS',
        'ALLERGEN_PEANUTS',
        'ALLERGEN_WHEAT',
        'ALLERGEN_BARLEY',
        'ALLERGEN_RYE',
        'ALLERGEN_OATS',
        'ALLERGEN_SOY',
        'ALLERGEN_SESAME',
        'ALLERGEN_SULFITES',
        'ALLERGEN_CELERY',
        'ALLERGEN_MUSTARD',
        'ALLERGEN_LUPIN',
      ];
      final out = ProfileState.migrateLegacyAllergenIds(canonical);
      expect(out.toSet(), canonical.toSet());

      // Idempotent on a second pass.
      final twice = ProfileState.migrateLegacyAllergenIds(out);
      expect(twice.toSet(), canonical.toSet());
    });

    test('deduplicates expansion overlaps', () {
      // User had both ALLERGEN_GLUTEN (expands to WHEAT+...) and
      // ALLERGEN_WHEAT explicitly. Result should not contain duplicate WHEAT.
      final out = ProfileState.migrateLegacyAllergenIds(const [
        'ALLERGEN_GLUTEN',
        'ALLERGEN_WHEAT',
      ]);
      expect(
        out.where((id) => id == 'ALLERGEN_WHEAT').length,
        1,
        reason: 'WHEAT must not be duplicated when both group + explicit',
      );
      expect(out.toSet(), {
        'ALLERGEN_WHEAT',
        'ALLERGEN_BARLEY',
        'ALLERGEN_RYE',
        'ALLERGEN_OATS',
      });
    });

    test('empty input yields empty output', () {
      expect(ProfileState.migrateLegacyAllergenIds(const []), isEmpty);
    });
  });
}
