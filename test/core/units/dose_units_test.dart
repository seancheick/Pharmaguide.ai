import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/units/dose_units.dart';

void main() {
  group('normalizeDoseUnit', () {
    test('folds all three microgram spellings to mcg', () {
      // The drift the audit caught: five files handle µ (U+00B5) while
      // depletion_checker only matched μ (U+03BC); only ul_checker knew "ug".
      expect(normalizeDoseUnit('µg'), 'mcg'); // U+00B5 MICRO SIGN
      expect(normalizeDoseUnit('μg'), 'mcg'); // U+03BC GREEK MU
      expect(normalizeDoseUnit('ug'), 'mcg'); // ASCII
      expect(normalizeDoseUnit('MCG'), 'mcg');
      expect(normalizeDoseUnit('  Mcg  '), 'mcg');
    });

    test('folds IU spellings', () {
      expect(normalizeDoseUnit('IU'), 'iu');
      expect(normalizeDoseUnit('I.U.'), 'iu');
      expect(normalizeDoseUnit('International Units'), 'iu');
      expect(normalizeDoseUnit('international unit'), 'iu');
      // Hyphenated / underscored spellings must also fold (idempotency fix).
      expect(normalizeDoseUnit('international-units'), 'iu');
      expect(normalizeDoseUnit('international_unit'), 'iu');
    });

    test('compound units keep their qualifier but fold the mass token', () {
      expect(normalizeDoseUnit('ug RAE'), 'mcg rae');
      expect(normalizeDoseUnit('µg DFE'), 'mcg dfe');
      expect(normalizeDoseUnit('mg alpha-tocopherol'), 'mg alpha tocopherol');
      expect(normalizeDoseUnit('mg NE'), 'mg ne');
    });

    test('does not corrupt non-microgram tokens', () {
      expect(normalizeDoseUnit('mg'), 'mg');
      expect(normalizeDoseUnit('g'), 'g');
      // "ug" only folds as a whole token, never as a substring.
      expect(normalizeDoseUnit('mcg'), 'mcg');
    });

    test('is idempotent', () {
      for (final u in ['µg', 'ug', 'I.U.', 'mg alpha-tocopherol', 'MCG']) {
        final once = normalizeDoseUnit(u);
        expect(normalizeDoseUnit(once), once, reason: u);
      }
    });
  });

  group('massGramsFactor', () {
    test('known mass units', () {
      expect(massGramsFactor('g'), 1.0);
      expect(massGramsFactor('mg'), 0.001);
      expect(massGramsFactor('mcg'), 0.000001);
      expect(massGramsFactor('µg'), 0.000001); // via normalization
      expect(massGramsFactor('ug'), 0.000001);
    });

    test('form-dependent units are not mass — returns null', () {
      expect(massGramsFactor('iu'), isNull);
      expect(massGramsFactor('mcg rae'), isNull);
      expect(massGramsFactor('mcg dfe'), isNull);
      expect(massGramsFactor(''), isNull);
    });
  });

  group('amountInMass', () {
    test('converts within the mass family', () {
      expect(amountInMass(1, from: 'g', to: 'mg'), 1000);
      expect(amountInMass(1000, from: 'mcg', to: 'mg'), closeTo(1.0, 1e-12));
      expect(amountInMass(20, from: 'mg', to: 'mg'), 20);
    });

    test('reconciles ug and mcg instead of declining (the audit bug)', () {
      // Before centralization, five files declined this and one UL surface
      // silently excluded the dose from the sum.
      expect(amountInMass(150, from: 'ug', to: 'mcg'), 150);
      expect(amountInMass(1, from: 'ug', to: 'mg'), closeTo(0.001, 1e-12));
    });

    test('declines form-dependent or empty units (never guesses IU↔mg)', () {
      expect(amountInMass(400, from: 'iu', to: 'mg'), isNull);
      expect(amountInMass(20, from: 'mg', to: 'iu'), isNull);
      expect(amountInMass(20, from: '', to: 'mg'), isNull);
      expect(amountInMass(20, from: 'mg', to: ''), isNull);
    });
  });
}
