import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/util/ingredient_display.dart';

void main() {
  group('prettifyIngredientName — branded / standardized forms', () {
    test('ksm_66 → KSM-66', () {
      expect(prettifyIngredientName('ksm_66'), 'KSM-66');
    });

    test('ksm66 alias also resolves to KSM-66', () {
      expect(prettifyIngredientName('ksm66'), 'KSM-66');
    });

    test('vitamin_d3 → Vitamin D3', () {
      expect(prettifyIngredientName('vitamin_d3'), 'Vitamin D3');
    });

    test('vitamin_k2 → Vitamin K2', () {
      expect(prettifyIngredientName('vitamin_k2'), 'Vitamin K2');
    });

    test('coq10 → CoQ10', () {
      expect(prettifyIngredientName('coq10'), 'CoQ10');
    });

    test('l_theanine → L-Theanine', () {
      expect(prettifyIngredientName('l_theanine'), 'L-Theanine');
    });

    test('omega_3 → Omega-3', () {
      expect(prettifyIngredientName('omega_3'), 'Omega-3');
    });

    test('bioperine → BioPerine', () {
      expect(prettifyIngredientName('bioperine'), 'BioPerine');
    });

    test('sam_e → SAM-e', () {
      expect(prettifyIngredientName('sam_e'), 'SAM-e');
    });
  });

  group('prettifyIngredientName — title-case fallback', () {
    test('magnesium_glycinate → Magnesium Glycinate', () {
      expect(prettifyIngredientName('magnesium_glycinate'),
          'Magnesium Glycinate');
    });

    test('ashwagandha → Ashwagandha', () {
      expect(prettifyIngredientName('ashwagandha'), 'Ashwagandha');
    });

    test('rhodiola_rosea → Rhodiola Rosea', () {
      expect(prettifyIngredientName('rhodiola_rosea'), 'Rhodiola Rosea');
    });

    test('mixed case input is normalized before title-casing', () {
      expect(prettifyIngredientName('Rhodiola_Rosea'), 'Rhodiola Rosea');
    });

    test('leading/trailing whitespace ignored', () {
      expect(prettifyIngredientName('  ashwagandha  '), 'Ashwagandha');
    });

    test('repeated underscores collapse to single space', () {
      expect(prettifyIngredientName('foo__bar'), 'Foo Bar');
    });

    // Live-test fix (2026-04-29): the score-breakdown payload ships
    // `ingredient_points` keys with whitespace separators ("vitamin c",
    // "vitamin b6", "pantothenic acid vitamin b5") instead of the
    // underscored form used elsewhere. The original implementation
    // split on `_` only, so "vitamin c" rendered as "Vitamin c"
    // (single-character title-casing). We now normalize whitespace
    // runs to underscores before lookup AND fallback splitting.
    test('space-separated key matches branded map (vitamin c → Vitamin C)',
        () {
      expect(prettifyIngredientName('vitamin c'), 'Vitamin C');
    });

    test('space-separated key matches branded map (vitamin b6 → Vitamin B6)',
        () {
      expect(prettifyIngredientName('vitamin b6'), 'Vitamin B6');
    });

    test('space-separated alias (ksm 66 → KSM-66)', () {
      expect(prettifyIngredientName('ksm 66'), 'KSM-66');
    });

    test('multi-word fallback title-cases per word, not per first char', () {
      expect(prettifyIngredientName('pantothenic acid vitamin b5'),
          'Pantothenic Acid Vitamin B5');
      expect(
          prettifyIngredientName('magnesium glycinate'), 'Magnesium Glycinate');
    });

    test('mixed underscore + space separators normalize the same way', () {
      expect(prettifyIngredientName('zinc picolinate'), 'Zinc Picolinate');
      expect(prettifyIngredientName('zinc_picolinate'), 'Zinc Picolinate');
    });
  });

  group('prettifyIngredientName — edge cases', () {
    test('empty string → empty string', () {
      expect(prettifyIngredientName(''), '');
    });

    test('only whitespace → empty string', () {
      expect(prettifyIngredientName('   '), '');
    });
  });

  group('researchMatchSummary', () {
    test('0 returns null so caller can drop the bullet', () {
      expect(researchMatchSummary(0), isNull);
    });

    test('negative returns null', () {
      expect(researchMatchSummary(-3), isNull);
    });

    test('1 → singular phrasing', () {
      expect(researchMatchSummary(1),
          'One ingredient backed by clinical research');
    });

    test('3 → plural with numeric count', () {
      expect(researchMatchSummary(3),
          '3 ingredients backed by clinical research');
    });

    test('large count uses numeric, not "many"', () {
      expect(researchMatchSummary(42),
          '42 ingredients backed by clinical research');
    });
  });
}
