// ID-stability contract for the clinical-signal envelope (execution brief §3.1).
// These tests ENCODE the identity design: what a signal id must be invariant to
// (re-eval, subject order, case/whitespace, stack churn for cumulative exposure)
// and what it must be sensitive to (rule, family, nutrient). If the lifecycle
// layer is to track new/ongoing/changed/resolved, these invariants must hold.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/clinical_signal.dart';

void main() {
  group('deriveSignalId — deterministic per-family identity', () {
    test('is deterministic and non-empty for identical inputs', () {
      final a = deriveSignalId(
        family: SignalFamily.pairwiseInteraction,
        sourceRuleId: 'rule_1',
        subjectIds: const ['warfarin', 'fish_oil'],
      );
      final b = deriveSignalId(
        family: SignalFamily.pairwiseInteraction,
        sourceRuleId: 'rule_1',
        subjectIds: const ['warfarin', 'fish_oil'],
      );
      expect(a, b);
      expect(a, isNotEmpty);
    });

    test('pairwise id is subject-order invariant (A×B == B×A)', () {
      final ab = deriveSignalId(
        family: SignalFamily.pairwiseInteraction,
        sourceRuleId: 'r',
        subjectIds: const ['warfarin', 'fish_oil'],
      );
      final ba = deriveSignalId(
        family: SignalFamily.pairwiseInteraction,
        sourceRuleId: 'r',
        subjectIds: const ['fish_oil', 'warfarin'],
      );
      expect(ab, ba);
    });

    test('subject normalization — case and surrounding whitespace ignored', () {
      final messy = deriveSignalId(
        family: SignalFamily.pairwiseInteraction,
        sourceRuleId: 'r',
        subjectIds: const ['Warfarin', ' Fish_Oil '],
      );
      final clean = deriveSignalId(
        family: SignalFamily.pairwiseInteraction,
        sourceRuleId: 'r',
        subjectIds: const ['warfarin', 'fish_oil'],
      );
      expect(messy, clean);
    });

    test('different source rule id → different id', () {
      final r1 = deriveSignalId(
        family: SignalFamily.pairwiseInteraction,
        sourceRuleId: 'rule_1',
        subjectIds: const ['a', 'b'],
      );
      final r2 = deriveSignalId(
        family: SignalFamily.pairwiseInteraction,
        sourceRuleId: 'rule_2',
        subjectIds: const ['a', 'b'],
      );
      expect(r1, isNot(r2));
    });

    test('different family → different id for otherwise-identical inputs', () {
      final pairwise = deriveSignalId(
        family: SignalFamily.pairwiseInteraction,
        sourceRuleId: 'r',
        subjectIds: const ['a'],
      );
      final medProfile = deriveSignalId(
        family: SignalFamily.medicationProfile,
        sourceRuleId: 'r',
        subjectIds: const ['a'],
      );
      expect(pairwise, isNot(medProfile));
    });

    test('cumulative-exposure id depends ONLY on the nutrient, not products', () {
      // Same nutrient, different (ignored) product/rule inputs → SAME id, so the
      // signal survives products being added to / removed from the stack.
      final withProducts = deriveSignalId(
        family: SignalFamily.cumulativeExposure,
        nutrientId: 'vitamin_d',
        subjectIds: const ['product_a', 'product_b'],
        sourceRuleId: 'ignored',
      );
      final bare = deriveSignalId(
        family: SignalFamily.cumulativeExposure,
        nutrientId: 'vitamin_d',
      );
      expect(withProducts, bare);
    });

    test('cumulative-exposure id differs per nutrient', () {
      final d = deriveSignalId(
        family: SignalFamily.cumulativeExposure,
        nutrientId: 'vitamin_d',
      );
      final a = deriveSignalId(
        family: SignalFamily.cumulativeExposure,
        nutrientId: 'vitamin_a',
      );
      expect(d, isNot(a));
    });

    test('rejects missing identity inputs per family', () {
      expect(
        () => deriveSignalId(
          family: SignalFamily.pairwiseInteraction,
          subjectIds: const ['a'],
        ),
        throwsArgumentError,
        reason: 'pairwise identity requires a sourceRuleId',
      );
      expect(
        () => deriveSignalId(family: SignalFamily.cumulativeExposure),
        throwsArgumentError,
        reason: 'cumulative-exposure identity requires a nutrientId',
      );
    });
  });
}
