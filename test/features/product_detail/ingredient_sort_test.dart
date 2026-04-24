// FLTR-9 — active-ingredient display order.
//
// Two-bucket sort: disclosed first, undisclosed last, pipeline
// order preserved within each bucket. No cross-unit dose
// comparison (that's Release C / pipeline scope).

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/ingredient_sort.dart';

void main() {
  group('sortActivesForDisplay', () {
    test('puts disclosed-dose ingredients before undisclosed', () {
      final out = sortActivesForDisplay([
        <String, dynamic>{'standard_name': 'NoDose A', 'quantity': null},
        <String, dynamic>{'standard_name': 'Disclosed', 'quantity': 10},
        <String, dynamic>{'standard_name': 'NoDose B', 'quantity': 0},
      ]);
      expect(
        out.map((i) => i['standard_name']).toList(),
        ['Disclosed', 'NoDose A', 'NoDose B'],
      );
    });

    test('preserves pipeline order within each bucket', () {
      final out = sortActivesForDisplay([
        <String, dynamic>{'standard_name': 'A', 'quantity': 100},
        <String, dynamic>{'standard_name': 'B', 'quantity': 50},
        <String, dynamic>{'standard_name': 'C', 'quantity': null},
        <String, dynamic>{'standard_name': 'D', 'quantity': 25},
        <String, dynamic>{'standard_name': 'E', 'quantity': null},
      ]);
      // A, B, D were declared in that order on the label. Bucket
      // stability preserves it — no dose desc sort (units may
      // differ across rows).
      expect(
        out.map((i) => i['standard_name']).toList(),
        ['A', 'B', 'D', 'C', 'E'],
      );
    });

    test('treats zero and negative quantity as undisclosed', () {
      final out = sortActivesForDisplay([
        <String, dynamic>{'standard_name': 'Neg', 'quantity': -5},
        <String, dynamic>{'standard_name': 'Zero', 'quantity': 0},
        <String, dynamic>{'standard_name': 'Positive', 'quantity': 1},
      ]);
      expect(
        out.map((i) => i['standard_name']).toList(),
        ['Positive', 'Neg', 'Zero'],
      );
    });

    test('treats non-numeric quantity as undisclosed', () {
      final out = sortActivesForDisplay([
        <String, dynamic>{'standard_name': 'String', 'quantity': '10'},
        <String, dynamic>{'standard_name': 'Numeric', 'quantity': 5},
      ]);
      // String "10" is not a num — classified undisclosed even
      // though it looks like a number. Prevents accidental
      // coercion-based sorts on malformed blob data.
      expect(
        out.map((i) => i['standard_name']).toList(),
        ['Numeric', 'String'],
      );
    });

    test('empty input returns empty list', () {
      expect(sortActivesForDisplay(const []), isEmpty);
    });

    test('single-element input is returned unchanged', () {
      final only = [
        <String, dynamic>{'standard_name': 'Only', 'quantity': 10}
      ];
      final out = sortActivesForDisplay(only);
      expect(out, hasLength(1));
      expect(out.first['standard_name'], 'Only');
    });

    test('input list is not mutated', () {
      final input = <Map<String, dynamic>>[
        {'standard_name': 'NoDose', 'quantity': null},
        {'standard_name': 'Disclosed', 'quantity': 10},
      ];
      final before = input.map((i) => i['standard_name']).toList();
      sortActivesForDisplay(input);
      final after = input.map((i) => i['standard_name']).toList();
      expect(before, after, reason: 'caller list must stay as-is');
    });
  });
}
