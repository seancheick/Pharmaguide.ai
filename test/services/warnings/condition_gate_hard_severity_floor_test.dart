// Regression: the condition-threshold gate (`_isFullyGated`, exercised
// via `applyConditionThresholdGate`) must NEVER dose-suppress a hard
// contraindicated / avoid warning.
//
// Defect (P1, under-warning direction): `_isFullyGated` suppressed any
// condition-tagged warning whose dose fell below the app's const-table
// minDose, WITHOUT checking `warning.severity`. Its sibling
// `applyEmittedFloorGate` explicitly exempts contraindicated / avoid
// from dose-suppression — but `_isFullyGated` runs FIRST
// (product_detail_helpers.dart:69, before applyEmittedFloorGate at :77),
// so a hard warning below the app's minDose was fully gated and DROPPED
// before the floor gate's exemption could save it.
//
// Scenario: 100 mg ginkgo + surgery_scheduled. Pipeline emits an
// `avoid` "stop 2 weeks pre-op" warning. App table says ginkgo aboveDose
// 120 mg → 100 < 120 → pre-fix the avoid warning was dropped.
//
// Fix: `_isFullyGated` returns false (KEEP) immediately for
// contraindicated / avoid severity, mirroring `applyEmittedFloorGate`.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

InteractionWarning _w({
  required List<String> conditionIds,
  String? ingredientName,
  required Severity severity,
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
  group('_isFullyGated hard-severity floor — contraindicated / avoid', () {
    test('avoid ginkgo 100 mg + surgery_scheduled (below 120 mg) → KEPT', () {
      // The headline defect: an avoid "stop 2 weeks pre-op" warning below
      // the app's 120 mg minDose must NOT be dose-suppressed.
      final warning = _w(
        conditionIds: ['surgery_scheduled'],
        ingredientName: 'Ginkgo',
        severity: Severity.avoid,
      );
      final result = applyConditionThresholdGate(
        warnings: [warning],
        ingredientDoses: {'ginkgo': (value: 100, unit: 'mg')},
      );
      expect(result, hasLength(1));
      expect(result.single, same(warning));
    });

    test('contraindicated ginkgo 100 mg + surgery_scheduled → KEPT', () {
      final warning = _w(
        conditionIds: ['surgery_scheduled'],
        ingredientName: 'Ginkgo',
        severity: Severity.contraindicated,
      );
      final result = applyConditionThresholdGate(
        warnings: [warning],
        ingredientDoses: {'ginkgo': (value: 100, unit: 'mg')},
      );
      expect(result, hasLength(1));
    });
  });

  group('_isFullyGated dose gate still applies to soft severities', () {
    test('caution ginkgo 100 mg + surgery_scheduled (below 120 mg) → '
        'suppressed (gates as before)', () {
      final result = applyConditionThresholdGate(
        warnings: [
          _w(
            conditionIds: ['surgery_scheduled'],
            ingredientName: 'Ginkgo',
            severity: Severity.caution,
          ),
        ],
        ingredientDoses: {'ginkgo': (value: 100, unit: 'mg')},
      );
      expect(
        result,
        isEmpty,
        reason: 'soft severity below minDose still dose-gates as before',
      );
    });

    test('monitor ginkgo 100 mg + surgery_scheduled → suppressed', () {
      final result = applyConditionThresholdGate(
        warnings: [
          _w(
            conditionIds: ['surgery_scheduled'],
            ingredientName: 'Ginkgo',
            severity: Severity.monitor,
          ),
        ],
        ingredientDoses: {'ginkgo': (value: 100, unit: 'mg')},
      );
      expect(result, isEmpty);
    });

    test('caution ginkgo 150 mg (above 120 mg) → KEPT (dose fires)', () {
      // Control: the dose gate itself still fires above threshold for
      // soft severities — the fix only exempts hard severities.
      final result = applyConditionThresholdGate(
        warnings: [
          _w(
            conditionIds: ['surgery_scheduled'],
            ingredientName: 'Ginkgo',
            severity: Severity.caution,
          ),
        ],
        ingredientDoses: {'ginkgo': (value: 150, unit: 'mg')},
      );
      expect(result, hasLength(1));
    });
  });
}
