// Regression: selenium / thyroid_disorder must be UL-dose-gated, not a
// never-flag `positive` entry.
//
// Defect (P1, under-warning direction): the `selenium` entry under
// `thyroid_disorder` was `ConditionThreshold.positive()`, which (a)
// suppressed the thyroid warning at ANY dose — including 800 mcg, 2x
// the 400 mcg adult UL and squarely in the selenosis range — and (b)
// made selenium eligible for a "Selenium supports your thyroid health"
// positive benefit bullet on the Personal Fit card, actively
// encouraging a toxic-dose product. The entry's own rationale says
// "flag only above UL".
//
// Fix: dose-gate at the 400 mcg adult UL (mirrors the sibling `iodine`
// aboveDose entry). Below UL behaves as before (suppressed); at/above
// UL the warning surfaces; and selenium is no longer a positive bullet.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';
import 'package:pharmaguide/services/warnings/condition_thresholds.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

InteractionWarning _w({
  required List<String> conditionIds,
  String? ingredientName,
  Severity severity = Severity.monitor,
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: EvidenceLevel.theoretical,
    title: 'Test warning',
    mechanism: 'Test mechanism',
    management: 'Test management',
    conditionIds: conditionIds,
    ingredientName: ingredientName,
  );
}

void main() {
  group('selenium / thyroid_disorder threshold entry', () {
    test('is dose-gated (neutral) at the 400 mcg adult UL, NOT positive', () {
      final entry = lookupConditionThreshold(
        conditionId: 'thyroid_disorder',
        ingredientName: 'Selenium',
      );
      expect(entry, isNotNull);
      expect(
        entry!.directionality,
        NutrientDirectionality.neutral,
        reason: 'selenium must fire above UL, not be a never-flag positive',
      );
      expect(entry.minDose, 400);
      expect(entry.doseUnit, 'mcg');
    });
  });

  group('applyConditionThresholdGate — selenium / thyroid_disorder', () {
    test('800 mcg (2x UL, selenosis range) → warning KEPT (not suppressed)', () {
      final warning = _w(
        conditionIds: ['thyroid_disorder'],
        ingredientName: 'Selenium',
      );
      final result = applyConditionThresholdGate(
        warnings: [warning],
        ingredientDoses: {'selenium': (value: 800, unit: 'mcg')},
      );
      expect(result, hasLength(1));
      expect(result.single, same(warning));
    });

    test('exactly 400 mcg (at UL) → warning KEPT (boundary fires)', () {
      final result = applyConditionThresholdGate(
        warnings: [
          _w(conditionIds: ['thyroid_disorder'], ingredientName: 'Selenium'),
        ],
        ingredientDoses: {'selenium': (value: 400, unit: 'mcg')},
      );
      expect(result, hasLength(1));
    });

    test('200 mcg (sub-UL) → suppressed (gated as before)', () {
      final result = applyConditionThresholdGate(
        warnings: [
          _w(conditionIds: ['thyroid_disorder'], ingredientName: 'Selenium'),
        ],
        ingredientDoses: {'selenium': (value: 200, unit: 'mcg')},
      );
      expect(result, isEmpty);
    });
  });

  group('generatePositiveProfileBullets — selenium is NOT a benefit', () {
    test('Selenium + thyroid_disorder emits NO positive bullet', () {
      final bullets = generatePositiveProfileBullets(
        ingredientNames: const ['Selenium'],
        userConditionIds: const ['thyroid_disorder'],
      );
      expect(
        bullets,
        isEmpty,
        reason:
            'a UL-gated risk must not surface as "supports your thyroid '
            'health" — that encourages a toxic-dose product',
      );
    });
  });
}
