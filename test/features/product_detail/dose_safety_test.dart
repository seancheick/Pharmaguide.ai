// FLTR-11 — Dose-vs-UL safety predicate.
//
// Asserts [ingredientExceedsUl] fires when the disclosed dose beats
// either the age-default `ul_19_30` or the fallback `highest_ul`,
// and returns false when data is missing, non-positive, or the dose
// sits at or below the UL.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/dose_safety.dart';

void main() {
  group('ingredientExceedsUl', () {
    test('Vitamin A 25,000 IU vs 10,000 IU UL → exceeds', () {
      final ingredient = <String, dynamic>{
        'name': 'Vitamin A Palmitate',
        'amount': 25000,
        'unit': 'IU',
        'ul_19_30': 10000,
        'highest_ul': 10000,
      };
      expect(ingredientExceedsUl(ingredient), isTrue);
    });

    test('dose equal to UL is not over — strict >', () {
      final ingredient = <String, dynamic>{
        'amount': 10000,
        'ul_19_30': 10000,
      };
      expect(ingredientExceedsUl(ingredient), isFalse);
    });

    test('dose below UL returns false', () {
      final ingredient = <String, dynamic>{
        'amount': 5000,
        'ul_19_30': 10000,
      };
      expect(ingredientExceedsUl(ingredient), isFalse);
    });

    test('prefers ul_19_30 when both are present', () {
      // If the age-default were ignored, the falsy highest_ul would
      // let this slip through. Assert the priority order.
      final ingredient = <String, dynamic>{
        'amount': 3500,
        'ul_19_30': 3000,
        'highest_ul': 10000,
      };
      expect(ingredientExceedsUl(ingredient), isTrue);
    });

    test('falls back to highest_ul when ul_19_30 is absent', () {
      final ingredient = <String, dynamic>{
        'amount': 12000,
        'highest_ul': 10000,
      };
      expect(ingredientExceedsUl(ingredient), isTrue);
    });

    test('returns false when amount is missing', () {
      final ingredient = <String, dynamic>{
        'ul_19_30': 10000,
      };
      expect(ingredientExceedsUl(ingredient), isFalse);
    });

    test('returns false when amount is null (undisclosed dose)', () {
      final ingredient = <String, dynamic>{
        'amount': null,
        'ul_19_30': 10000,
      };
      expect(ingredientExceedsUl(ingredient), isFalse);
    });

    test('returns false when UL fields are missing', () {
      final ingredient = <String, dynamic>{
        'amount': 5000,
      };
      expect(ingredientExceedsUl(ingredient), isFalse);
    });

    test('handles string-encoded numeric amount', () {
      final ingredient = <String, dynamic>{
        'amount': '25000',
        'ul_19_30': 10000,
      };
      expect(ingredientExceedsUl(ingredient), isTrue);
    });

    test('handles string-encoded UL', () {
      final ingredient = <String, dynamic>{
        'amount': 12000,
        'ul_19_30': '10000',
      };
      expect(ingredientExceedsUl(ingredient), isTrue);
    });

    test('zero UL is treated as unknown (never fires)', () {
      final ingredient = <String, dynamic>{
        'amount': 5000,
        'ul_19_30': 0,
      };
      expect(ingredientExceedsUl(ingredient), isFalse);
    });

    test('negative amount is treated as unknown', () {
      final ingredient = <String, dynamic>{
        'amount': -1,
        'ul_19_30': 10000,
      };
      expect(ingredientExceedsUl(ingredient), isFalse);
    });

    test('non-numeric garbage does not throw, returns false', () {
      final ingredient = <String, dynamic>{
        'amount': 'abc',
        'ul_19_30': 'xyz',
      };
      expect(ingredientExceedsUl(ingredient), isFalse);
    });
  });
}
