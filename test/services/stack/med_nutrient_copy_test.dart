// Safety-copy contract for the Medication & Nutrient Monitor (B1.1, PM-locked
// 2026-07-23). Copy is generated from explicit relationship_type × supply_state
// templates — never one interpolated universal sentence. It must stay factual:
// no "covered"/"adequate"/replacement claims, no internal comparison-threshold
// language, amounts carry a per-day basis, and it never implies a measured
// deficiency or physiological sufficiency.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

const _banned = [
  'covered',
  'adequate',
  'replenish',
  'corrected',
  'protected',
  'replace',
];

void _assertNoBannedWords(String copy) {
  final lower = copy.toLowerCase();
  for (final w in _banned) {
    expect(
      lower.contains(w),
      isFalse,
      reason: 'banned word "$w" appeared in: $copy',
    );
  }
}

void main() {
  group('medNutrientSupplyStateFrom', () {
    test('maps coverage bands + amount availability', () {
      expect(
        medNutrientSupplyStateFrom(CoverageLevel.none, hasAmount: false),
        MedNutrientSupplyState.noDetectedSource,
      );
      expect(
        medNutrientSupplyStateFrom(CoverageLevel.partial, hasAmount: true),
        MedNutrientSupplyState.sourceDetectedBelowComparison,
      );
      expect(
        medNutrientSupplyStateFrom(CoverageLevel.adequate, hasAmount: true),
        MedNutrientSupplyState.meetsComparisonAmount,
      );
      expect(
        medNutrientSupplyStateFrom(CoverageLevel.adequate, hasAmount: false),
        MedNutrientSupplyState.sourceAmountUnknown,
      );
    });
  });

  group('medNutrientBodyCopy — depletion supply states', () {
    String copy(
      MedNutrientSupplyState s, {
      num? detected,
      String? unit,
      num? comp,
      String? compUnit,
    }) => medNutrientBodyCopy(
      relationshipType: 'depletion',
      nutrient: 'Vitamin B12',
      subject: 'Metformin',
      supplyState: s,
      detectedAmount: detected,
      detectedUnit: unit,
      comparisonAmount: comp,
      comparisonUnit: compUnit,
    );

    test('no source detected', () {
      final c = copy(MedNutrientSupplyState.noDetectedSource);
      expect(
        c,
        contains('No Vitamin B12 source detected in your current stack'),
      );
      expect(
        c,
        contains(
          'Metformin use has been associated with lower Vitamin B12 status',
        ),
      );
      expect(c, contains('Consider asking your clinician'));
      _assertNoBannedWords(c);
    });

    test('detected amount uses plain per-day supply copy', () {
      final c = copy(
        MedNutrientSupplyState.sourceDetectedBelowComparison,
        detected: 50,
        unit: 'mcg',
        comp: 100,
        compUnit: 'mcg',
      );
      expect(c, contains('Your stack provides 50 mcg/day of Vitamin B12'));
      expect(c, contains('does not confirm your blood level'));
      expect(c, isNot(contains('comparison amount')));
      _assertNoBannedWords(c);
    });

    test('threshold state never becomes a sufficiency claim', () {
      final c = copy(
        MedNutrientSupplyState.meetsComparisonAmount,
        detected: 250,
        unit: 'mcg',
        comp: 100,
        compUnit: 'mcg',
      );
      expect(c, contains('Your stack provides 250 mcg/day of Vitamin B12'));
      expect(c, isNot(contains('comparison amount')));
      expect(
        c,
        contains('does not confirm your blood level or nutrient status'),
      );
      _assertNoBannedWords(c);
    });

    test('amount unknown', () {
      final c = copy(MedNutrientSupplyState.sourceAmountUnknown);
      expect(c, contains('Your stack includes Vitamin B12'));
      expect(c, contains('daily amount could not be determined'));
      _assertNoBannedWords(c);
    });

    test('below comparison with no amount degrades to amount-unknown', () {
      final c = copy(MedNutrientSupplyState.sourceDetectedBelowComparison);
      expect(c, contains('could not be determined'));
      expect(c, isNot(contains('contains  of')));
      _assertNoBannedWords(c);
    });
  });

  group('medNutrientBodyCopy — relationship-specific', () {
    String copy(String type) => medNutrientBodyCopy(
      relationshipType: type,
      nutrient: 'Magnesium',
      subject: 'Furosemide',
    );

    test('functional_antagonism uses "the body", denies low-level claim', () {
      final c = copy('functional_antagonism');
      expect(c, contains('Furosemide may affect how the body uses Magnesium'));
      expect(c, contains('does not confirm that your Magnesium level is low'));
      expect(c, isNot(contains('your body')));
      _assertNoBannedWords(c);
    });

    test('monitoring_stability is clinical, not casual', () {
      final c = copy('monitoring_stability');
      expect(
        c,
        contains(
          'Monitoring Magnesium may be relevant while taking Furosemide',
        ),
      );
      expect(c, contains('Ask your clinician whether testing or follow-up'));
      expect(c, isNot(contains('Keep an eye')));
      _assertNoBannedWords(c);
    });

    test('supplement_interaction is generic, defers to details', () {
      final c = copy('supplement_interaction');
      expect(c, contains('Magnesium may interact with Furosemide'));
      expect(
        c,
        contains('discuss timing or use with your clinician or pharmacist'),
      );
      _assertNoBannedWords(c);
    });
  });

  group('medNutrientBodyCopy — condition_related', () {
    test('uses the condition subject, not "medication-related"', () {
      final c = medNutrientBodyCopy(
        relationshipType: 'condition_related',
        nutrient: 'Vitamin D',
        subject: 'Chronic kidney disease',
        supplyState: MedNutrientSupplyState.sourceDetectedBelowComparison,
        detectedAmount: 1000,
        detectedUnit: 'IU',
      );
      expect(
        c,
        contains(
          'Vitamin D may be relevant to monitor with Chronic kidney disease',
        ),
      );
      expect(
        c,
        contains('Your current stack contains 1000 IU of Vitamin D per day'),
      );
      expect(c, isNot(contains('medication-related')));
      _assertNoBannedWords(c);
    });
  });

  test('unknown relationship type falls back to a safe informational line', () {
    final c = medNutrientBodyCopy(
      relationshipType: 'novel_type',
      nutrient: 'Zinc',
      subject: 'Drug X',
    );
    _assertNoBannedWords(c);
    expect(c, contains('Zinc'));
    expect(c.toLowerCase(), isNot(contains('deplet')));
  });
}
