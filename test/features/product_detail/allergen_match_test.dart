import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/allergen_match.dart';

void main() {
  group('matchAllergens', () {
    test('returns empty when user has no allergens', () {
      final matches = matchAllergens(
        const [],
        _structured([
          {'allergen_id': 'ALLERGEN_SOY', 'presence_type': 'contains'},
        ]),
      );
      expect(matches, isEmpty);
    });

    test('returns empty when product has no allergens', () {
      final matches = matchAllergens(const ['ALLERGEN_SOY'], null);
      expect(matches, isEmpty);
    });

    test('returns empty when product allergens is empty list', () {
      final matches = matchAllergens(const ['ALLERGEN_SOY'], const <dynamic>[]);
      expect(matches, isEmpty);
    });

    test('exact match returns one entry with all fields populated', () {
      final matches = matchAllergens(
        const ['ALLERGEN_SOY'],
        _structured([
          {
            'allergen_id': 'ALLERGEN_SOY',
            'display_name': 'Soy & Soy Lecithin',
            'presence_type': 'contains',
            'severity_level': 'low',
            'evidence': 'Contains: Soy',
          },
        ]),
      );
      expect(matches, hasLength(1));
      expect(matches.first.id, 'ALLERGEN_SOY');
      expect(matches.first.displayName, 'Soy & Soy Lecithin');
      expect(matches.first.presenceType, 'contains');
      expect(matches.first.severityLevel, 'low');
      expect(matches.first.evidence, 'Contains: Soy');
    });

    test('non-match is skipped (substring matching is forbidden)', () {
      // SOYBEAN is not a canonical ID — must NOT match SOY by substring.
      final matches = matchAllergens(
        const ['ALLERGEN_SOYBEAN'],
        _structured([
          {'allergen_id': 'ALLERGEN_SOY', 'presence_type': 'contains'},
        ]),
      );
      expect(matches, isEmpty);
    });

    test('multiple matches are sorted by presence_type priority', () {
      final matches = matchAllergens(
        const ['ALLERGEN_SOY', 'ALLERGEN_TREE_NUTS', 'ALLERGEN_PEANUTS'],
        _structured([
          {
            'allergen_id': 'ALLERGEN_PEANUTS',
            'presence_type': 'manufactured_in_facility',
            'severity_level': 'high',
          },
          {
            'allergen_id': 'ALLERGEN_TREE_NUTS',
            'presence_type': 'may_contain',
            'severity_level': 'high',
          },
          {
            'allergen_id': 'ALLERGEN_SOY',
            'presence_type': 'contains',
            'severity_level': 'low',
          },
        ]),
      );
      expect(matches.map((m) => m.id).toList(), [
        'ALLERGEN_SOY', // contains first, even with low severity
        'ALLERGEN_TREE_NUTS', // may_contain second
        'ALLERGEN_PEANUTS', // facility last
      ]);
    });

    test('within same presence_type, sorted by severity high→low', () {
      final matches = matchAllergens(
        const ['ALLERGEN_MILK', 'ALLERGEN_SOY', 'ALLERGEN_PEANUTS'],
        _structured([
          {
            'allergen_id': 'ALLERGEN_SOY',
            'presence_type': 'contains',
            'severity_level': 'low',
          },
          {
            'allergen_id': 'ALLERGEN_PEANUTS',
            'presence_type': 'contains',
            'severity_level': 'high',
          },
          {
            'allergen_id': 'ALLERGEN_MILK',
            'presence_type': 'contains',
            'severity_level': 'moderate',
          },
        ]),
      );
      expect(matches.map((m) => m.id).toList(), [
        'ALLERGEN_PEANUTS', // high
        'ALLERGEN_MILK', // moderate
        'ALLERGEN_SOY', // low
      ]);
    });

    test('falls back to defaults for missing optional fields', () {
      final matches = matchAllergens(
        const ['ALLERGEN_MILK'],
        _structured([
          {
            'allergen_id': 'ALLERGEN_MILK',
            // no display_name, no presence_type, no severity_level, no evidence
          },
        ]),
      );
      expect(matches, hasLength(1));
      expect(matches.first.displayName, 'ALLERGEN_MILK');
      expect(matches.first.presenceType, 'contains');
      expect(matches.first.severityLevel, 'moderate');
      expect(matches.first.evidence, isNull);
    });

    test('skips entries without an allergen_id', () {
      final matches = matchAllergens(
        const ['ALLERGEN_MILK'],
        _structured([
          {'display_name': 'Milk', 'presence_type': 'contains'}, // no id
          {
            'allergen_id': 'ALLERGEN_MILK',
            'presence_type': 'contains',
            'severity_level': 'moderate',
          },
        ]),
      );
      expect(matches, hasLength(1));
      expect(matches.first.id, 'ALLERGEN_MILK');
    });

    test('skips non-Map entries defensively', () {
      final matches = matchAllergens(
        const ['ALLERGEN_SOY'],
        const <dynamic>[
          'unexpected string',
          42,
          null,
          {
            'allergen_id': 'ALLERGEN_SOY',
            'presence_type': 'contains',
            'severity_level': 'low',
          },
        ],
      );
      expect(matches, hasLength(1));
      expect(matches.first.id, 'ALLERGEN_SOY');
    });

    test('empty evidence string is normalized to null', () {
      final matches = matchAllergens(
        const ['ALLERGEN_SOY'],
        _structured([
          {
            'allergen_id': 'ALLERGEN_SOY',
            'presence_type': 'contains',
            'evidence': '',
          },
        ]),
      );
      expect(matches.first.evidence, isNull);
    });
  });
}

List<dynamic> _structured(List<Map<String, dynamic>> entries) =>
    List<dynamic>.from(entries);
