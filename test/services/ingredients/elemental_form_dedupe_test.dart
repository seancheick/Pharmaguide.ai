// Tests for elemental vs compound display dedupe — mirrors the
// verified dsld_id 315678 blob shape (Double Wood Magnesium Glycinate
// 400 mg): TWO ingredient rows for one nutrient, elemental 60 mg +
// compound 400 mg, same canonical_id.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/ingredients_helpers.dart';
import 'package:pharmaguide/services/ingredients/elemental_form_dedupe.dart';

Map<String, dynamic> _elementalMg() => {
  'name': 'Magnesium',
  'standard_name': 'Magnesium',
  'quantity': 60,
  'unit': 'mg',
  'matched_form': 'magnesium glycinate',
  'canonical_id': 'magnesium',
  'form_status': 'known',
  'display_form_label': 'magnesium glycinate',
  'bio_score': 13.0,
};

Map<String, dynamic> _compoundMg() => {
  'name': 'Magnesium Glycinate',
  'standard_name': 'Magnesium Glycinate',
  'quantity': 400,
  'unit': 'mg',
  'matched_form': 'magnesium glycinate',
  'canonical_id': 'magnesium',
  'form_status': 'known',
  'display_form_label': 'magnesium glycinate',
  'bio_score': 13.0,
};

void main() {
  group('dedupeElementalCompoundRows — 315678 dual-row shape', () {
    test('renders ONE magnesium row: elemental dose + compound as form', () {
      final result = dedupeElementalCompoundRows([
        _elementalMg(),
        _compoundMg(),
      ]);

      expect(result, hasLength(1));
      final typed = activeFromMap(result.single);
      expect(typed.name, 'Magnesium (as Magnesium Glycinate)');
      expect(typed.dose, '60 mg');
      // Form-quality badge survives once via the elemental row.
      expect(typed.formLabel, 'magnesium glycinate');
    });

    test('order does not matter — compound row first', () {
      final result = dedupeElementalCompoundRows([
        _compoundMg(),
        _elementalMg(),
      ]);

      expect(result, hasLength(1));
      expect(activeFromMap(result.single).dose, '60 mg');
    });

    test('does not mutate input maps', () {
      final elemental = _elementalMg();
      dedupeElementalCompoundRows([elemental, _compoundMg()]);
      expect(elemental.containsKey('display_label'), isFalse);
    });

    test('unrelated ingredients pass through untouched', () {
      final zinc = {
        'name': 'Zinc',
        'quantity': 15,
        'unit': 'mg',
        'canonical_id': 'zinc',
      };
      final result = dedupeElementalCompoundRows([
        _elementalMg(),
        _compoundMg(),
        zinc,
      ]);
      expect(result, hasLength(2));
      expect(result.last, same(zinc));
    });
  });

  group('dedupeElementalCompoundRows — preserved cases', () {
    test('multi-form rows with NO bare elemental sibling render both', () {
      final oxide = {
        'name': 'Magnesium (as oxide)',
        'quantity': 200,
        'unit': 'mg',
        'canonical_id': 'magnesium',
      };
      final citrate = {
        'name': 'Magnesium (as citrate)',
        'quantity': 100,
        'unit': 'mg',
        'canonical_id': 'magnesium',
      };
      // Both names strip to the bare elemental name → all-elemental
      // group, no compound duplicate. Both rows survive.
      expect(dedupeElementalCompoundRows([oxide, citrate]), hasLength(2));

      final glycinate = {
        'name': 'Magnesium Glycinate',
        'quantity': 400,
        'unit': 'mg',
        'canonical_id': 'magnesium',
      };
      final taurate = {
        'name': 'Magnesium Taurate',
        'quantity': 200,
        'unit': 'mg',
        'canonical_id': 'magnesium',
      };
      // All-compound group (no bare elemental row) — left untouched.
      expect(dedupeElementalCompoundRows([glycinate, taurate]), hasLength(2));
    });

    test('rows without canonical_id are never grouped', () {
      final a = {'name': 'Magnesium', 'quantity': 60, 'unit': 'mg'};
      final b = {'name': 'Magnesium Glycinate', 'quantity': 400, 'unit': 'mg'};
      expect(dedupeElementalCompoundRows([a, b]), hasLength(2));
    });

    test('single row passes through', () {
      final result = dedupeElementalCompoundRows([_elementalMg()]);
      expect(result, hasLength(1));
      expect(activeFromMap(result.single).name, 'Magnesium');
    });
  });

  group('isElementalIngredientName', () {
    test('matches bare and parenthetical-stripped names', () {
      expect(isElementalIngredientName('Magnesium', 'magnesium'), isTrue);
      expect(
        isElementalIngredientName('Magnesium (elemental)', 'magnesium'),
        isTrue,
      );
      expect(
        isElementalIngredientName('Magnesium Glycinate', 'magnesium'),
        isFalse,
      );
      expect(isElementalIngredientName('Vitamin D3', 'vitamin_d3'), isTrue);
    });

    test('hyphenated label spellings match (B#3 regression)', () {
      // The old normalizer folded whitespace/underscore but NOT hyphens, so a
      // 'Vitamin-D3' / '5-HTP' label never matched its canonical id and the
      // elemental/compound dedup silently double-counted. canonicalizeIngredientName
      // folds hyphens (and applies aliases), so these now resolve.
      expect(isElementalIngredientName('Vitamin-D3', 'vitamin_d3'), isTrue);
      expect(isElementalIngredientName('5-HTP', '5_htp'), isTrue);
      expect(isElementalIngredientName('Co-Q10', 'co_q10'), isTrue);
      // Alias fold: 'Vitamin B3' is niacin.
      expect(isElementalIngredientName('Vitamin B3', 'niacin'), isTrue);
    });
  });
}
