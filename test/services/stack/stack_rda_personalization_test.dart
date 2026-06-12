// Regression lock for age/sex-personalized magnesium RDA targeting.
//
// Unlike stack_ul_checker_test.dart (hand-built fixture), this suite
// loads the REAL bundled asset `assets/reference_data/rda_optimal_uls.json`
// from disk and asserts that the NIH ODS magnesium RDAs flow through
// [StackUlChecker] exactly as published.
//
// SOURCE OF TRUTH: NIH ODS Magnesium Health Professional Fact Sheet,
// Table 1 (RDAs for Magnesium, mg/day), retrieved 2026-06-12:
//   Male 14-18: 410 | Female 14-18: 360
//   Male 19-30: 400 | Female 19-30: 310
//   Male 31-50: 420 | Female 31-50: 320
//   Male 51+:   420 | Female 51+:   320
// Supplemental UL: 350 mg for all adults.
//
// The app's profile age brackets ('14-18','19-30','31-50','51-70','71+'
// — see SchemaIds.ageBrackets) map 1:1 onto NIH rows; both '51-70' and
// '71+' carry the NIH 51+ values (Male 420 / Female 320).
//
// Anonymous / incomplete-profile behavior is the documented conservative
// baseline (Female 19-30 → 310 mg) flagged via `rdaIsBaseline`, NOT the
// adult-male 400 — see StackUlChecker._getRdaWithProvenance tier 3.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_ul_checker.dart';

void main() {
  late StackUlChecker checker;

  setUpAll(() {
    // flutter test runs with cwd = project root.
    final raw = File(
      'assets/reference_data/rda_optimal_uls.json',
    ).readAsStringSync();
    checker = StackUlChecker(rdaData: jsonDecode(raw) as Map<String, dynamic>);
  });

  Map<String, NutrientTotal> magnesiumStack(double mg) => {
    'magnesium': NutrientTotal(
      canonicalId: 'magnesium',
      displayName: 'Magnesium',
      totalAmount: mg,
      unit: 'mg',
      contributions: const [],
    ),
  };

  NutrientStatus mgStatus({String? ageBracket, String? sex}) {
    final results = checker.check(
      magnesiumStack(200),
      ageBracket: ageBracket,
      sex: sex,
    );
    expect(results, hasLength(1));
    return results.single;
  }

  group('NIH ODS Table 1 — personalized magnesium RDA', () {
    test('male 31-50 uses 420 mg target', () {
      final s = mgStatus(ageBracket: '31-50', sex: 'Male');
      expect(s.rda, 420);
      expect(s.pctOfRda, closeTo(200 / 420 * 100, 0.001));
      expect(s.rdaIsBaseline, isFalse);
    });

    test('female 19-30 uses 310 mg target', () {
      final s = mgStatus(ageBracket: '19-30', sex: 'Female');
      expect(s.rda, 310);
      expect(s.pctOfRda, closeTo(200 / 310 * 100, 0.001));
      expect(s.rdaIsBaseline, isFalse);
    });

    test('all profile brackets match NIH rows exactly', () {
      const expected = {
        ('Male', '14-18'): 410.0,
        ('Male', '19-30'): 400.0,
        ('Male', '31-50'): 420.0,
        ('Male', '51-70'): 420.0, // NIH 51+ row
        ('Male', '71+'): 420.0, // NIH 51+ row
        ('Female', '14-18'): 360.0,
        ('Female', '19-30'): 310.0,
        ('Female', '31-50'): 320.0,
        ('Female', '51-70'): 320.0, // NIH 51+ row
        ('Female', '71+'): 320.0, // NIH 51+ row
      };
      for (final entry in expected.entries) {
        final (sex, bracket) = entry.key;
        final s = mgStatus(ageBracket: bracket, sex: sex);
        expect(
          s.rda,
          entry.value,
          reason: '$sex $bracket should use NIH RDA ${entry.value} mg',
        );
        expect(s.rdaIsBaseline, isFalse, reason: '$sex $bracket is exact');
      }
    });
  });

  group('fallback behavior (profile absent or incomplete)', () {
    test('missing profile falls back to flagged Female 19-30 baseline', () {
      final s = mgStatus();
      expect(s.rda, 310);
      expect(s.rdaIsBaseline, isTrue);
    });

    test('unknown age bracket falls back to flagged baseline', () {
      final s = mgStatus(ageBracket: '9-13', sex: 'Male');
      // '9-13' is not a profile bracket and has no adult row in the
      // bundled data — checker drops to the anonymous baseline.
      expect(s.rda, 310);
      expect(s.rdaIsBaseline, isTrue);
    });

    test('age known but sex unmatched uses the Female row at that age, '
        'FLAGGED — never silently the Male target', () {
      // sex null models 'Other' / 'Prefer not to say', which the
      // provider normalizes to null before calling the checker.
      final s = mgStatus(ageBracket: '31-50', sex: null);
      expect(s.rda, 320); // Female 31-50, not Male 420
      expect(s.rdaIsBaseline, isTrue);
    });

    test('age known but sex unmatched takes the lowest UL at that age, '
        'flagged', () {
      final s = mgStatus(ageBracket: '31-50', sex: null);
      expect(s.ul, 350);
      expect(s.ulIsFallback, isTrue);
    });
  });

  group('UL math is demographic-invariant for magnesium', () {
    test('supplemental UL is 350 mg for every adult demographic', () {
      const demos = [
        ('Male', '19-30'),
        ('Male', '31-50'),
        ('Female', '19-30'),
        ('Female', '51-70'),
      ];
      for (final (sex, bracket) in demos) {
        final s = mgStatus(ageBracket: bracket, sex: sex);
        expect(s.ul, 350, reason: '$sex $bracket UL must stay 350 mg');
        expect(s.pctOfUl, closeTo(200 / 350 * 100, 0.001));
      }
    });

    test('anonymous UL uses highest_ul fallback of 350 mg', () {
      final s = mgStatus();
      expect(s.ul, 350);
      expect(s.ulIsFallback, isTrue);
    });

    test('exceeding 350 mg fires exceedsUl regardless of sex', () {
      for (final sex in ['Male', 'Female']) {
        final results = checker.check(
          magnesiumStack(400),
          ageBracket: '31-50',
          sex: sex,
        );
        expect(results.single.tier, NutrientTier.exceedsUl);
      }
    });
  });
}
