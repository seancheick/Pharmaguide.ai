// canonicalizeIngredientName — extracted from condition_thresholds_test.dart
// alongside the function it covers
// (lib/services/ingredients/ingredient_canonicalizer.dart). Behavior is
// unchanged; the punctuation-strip test moved here verbatim.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/ingredients/ingredient_canonicalizer.dart';

void main() {
  group('canonicalizeIngredientName', () {
    test('T16.2e — strips punctuation (comma, parens)', () {
      // PureLean live walkthrough surfaced "Cinnamon Bark Extract,
      // Dried" leaking past the gate because pre-T16.2e canonicalize
      // preserved punctuation as literal characters in the key. This
      // anchors the punctuation-strip behavior for future regressions.
      expect(
        canonicalizeIngredientName('Cinnamon Bark Extract, Dried'),
        equals('cinnamon_bark_extract_dried'),
      );
      expect(
        canonicalizeIngredientName('Vitamin C (as ascorbic acid)'),
        equals('vitamin_c_as_ascorbic_acid'),
      );
      expect(
        canonicalizeIngredientName('Magnesium (oxide), USP'),
        equals('magnesium_oxide_usp'),
      );
      // Edge: leading/trailing punctuation collapsed and stripped.
      expect(canonicalizeIngredientName('(Iron)'), equals('iron'));
      // Pre-existing behavior preserved.
      expect(canonicalizeIngredientName('Vitamin D'), equals('vitamin_d'));
      expect(canonicalizeIngredientName('Vitamin-D3'), equals('vitamin_d3'));
    });

    test('niacin spellings collapse onto the single clinical key', () {
      // The alias map folds DSLD/pipeline niacin spellings onto `niacin`
      // so the clinical dose lookup keys the rule once. Previously untested.
      expect(canonicalizeIngredientName('Vitamin B3'), equals('niacin'));
      expect(canonicalizeIngredientName('Vitamin B-3'), equals('niacin'));
      expect(canonicalizeIngredientName('Vitamin B3 (Niacin)'), equals('niacin'));
    });

    test('empty / whitespace-only input returns empty', () {
      expect(canonicalizeIngredientName(''), equals(''));
      expect(canonicalizeIngredientName('   '), equals(''));
    });
  });
}
