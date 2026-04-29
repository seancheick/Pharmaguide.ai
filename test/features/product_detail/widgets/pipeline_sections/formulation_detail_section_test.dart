import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/pipeline_sections/formulation_detail_section.dart';

void main() {
  group('extractIngredientNames (T0.3)', () {
    test('current pipeline shape: list of maps with `name` field', () {
      final raw = [
        {
          'name': 'Ashwagandha (KSM-66)',
          'evidence_source': 'branded_form',
          'meets_threshold': true,
        },
        {'name': 'BioPerine', 'evidence_source': 'absorption_enhancer'},
      ];
      expect(extractIngredientNames(raw), [
        'Ashwagandha (KSM-66)',
        'BioPerine',
      ]);
    });

    test('legacy shape: plain list of strings still works', () {
      expect(extractIngredientNames(['Piperine', 'BioPerine']), [
        'Piperine',
        'BioPerine',
      ]);
    });

    test('mixed shape: strings and maps coexist', () {
      final raw = [
        'Piperine',
        {'name': 'Ashwagandha (KSM-66)'},
        'Black Pepper Extract',
      ];
      expect(extractIngredientNames(raw), [
        'Piperine',
        'Ashwagandha (KSM-66)',
        'Black Pepper Extract',
      ]);
    });

    test('empty list → empty list', () {
      expect(extractIngredientNames(<dynamic>[]), <String>[]);
    });

    test('null → empty list (no exception)', () {
      expect(extractIngredientNames(null), <String>[]);
    });

    test('non-list shape (Map) → empty list (no exception)', () {
      expect(
        extractIngredientNames({'name': 'Should not be picked up'}),
        <String>[],
      );
    });

    test('non-list shape (scalar) → empty list', () {
      expect(extractIngredientNames(42), <String>[]);
      expect(extractIngredientNames('not a list'), <String>[]);
    });

    test('map without `name` key drops silently', () {
      final raw = [
        {'evidence_source': 'orphan'},
        {'name': 'Curcumin'},
      ];
      expect(extractIngredientNames(raw), ['Curcumin']);
    });

    test('map with empty / whitespace `name` is dropped', () {
      final raw = [
        {'name': ''},
        {'name': '   '},
        {'name': 'Quercetin'},
      ];
      expect(extractIngredientNames(raw), ['Quercetin']);
    });

    test('strings are trimmed', () {
      expect(extractIngredientNames(['  Piperine  ', '\tBioPerine\n']), [
        'Piperine',
        'BioPerine',
      ]);
    });

    test('empty / whitespace strings are dropped', () {
      expect(extractIngredientNames(['', '   ', 'Resveratrol']), [
        'Resveratrol',
      ]);
    });

    test('no curly-brace JSON leak escapes the helper', () {
      final raw = [
        {
          'name': 'Ashwagandha (KSM-66)',
          'evidence_source': 'branded_form',
          'meets_threshold': true,
        },
      ];
      final out = extractIngredientNames(raw);
      expect(out, isNotEmpty);
      for (final name in out) {
        expect(name, isNot(contains('{')));
        expect(name, isNot(contains('}')));
        expect(name, isNot(contains('evidence_source')));
      }
    });
  });
}
