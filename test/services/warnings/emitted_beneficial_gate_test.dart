// Phase 2 of retiring condition_thresholds.dart — emitted-beneficial gate.
//
// The pipeline tags condition warnings for beneficial nutrients with
// `direction == 'beneficial'` (e.g. "Vitamin D3 / ttc — monitor"). Surfacing a
// monitor flag for a nutrient that HELPS the condition is the boy-who-cried-wolf
// false positive the const `positive` table was built to suppress. This gate is
// the pipeline-owned replacement, reading emitted `direction` instead of the
// Dart table. It runs ADDITIVELY alongside the const-table gate for now.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/product_detail_helpers.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

InteractionWarning _vitD({
  String? direction = 'beneficial',
  Severity severity = Severity.monitor,
  String? materiality = 'presence',
}) {
  return InteractionWarning(
    severity: severity,
    evidenceLevel: EvidenceLevel.established,
    title: 'Vitamin D3 / ttc',
    mechanism: 'Vitamin D supports fertility / pre-conception.',
    management: 'Continue as directed.',
    conditionIds: const ['ttc'],
    ingredientName: 'Vitamin D3',
    direction: direction,
    materiality: materiality,
  );
}

bool _hasVitD(List<InteractionWarning> ws) =>
    ws.any((w) => w.ingredientName == 'Vitamin D3');

void main() {
  group('applyEmittedBeneficialGate — direction=beneficial suppression', () {
    test('beneficial monitor warning → suppressed', () {
      expect(applyEmittedBeneficialGate([_vitD()]), isEmpty);
    });

    test('harmful warning → fires (only beneficial is suppressed)', () {
      expect(
        _hasVitD(applyEmittedBeneficialGate([_vitD(direction: 'harmful')])),
        isTrue,
      );
    });

    test('neutral warning → fires', () {
      expect(
        _hasVitD(applyEmittedBeneficialGate([_vitD(direction: 'neutral')])),
        isTrue,
      );
    });

    test('null direction (legacy blob) → fires (fail open)', () {
      expect(
        _hasVitD(applyEmittedBeneficialGate([_vitD(direction: null)])),
        isTrue,
      );
    });

    test('beneficial but hard severity (avoid) → still fires (severity floor)', () {
      // Mirrors applyEmittedFloorGate's guardrail: a hard warning is never
      // directionally suppressed, even if tagged beneficial. A beneficial +
      // avoid combination is a data contradiction that fails safe toward
      // warning (cf. the selenium/thyroid _isFullyGated severity-floor fix).
      expect(
        _hasVitD(applyEmittedBeneficialGate([_vitD(severity: Severity.avoid)])),
        isTrue,
      );
    });

    test('beneficial but contraindicated → still fires (severity floor)', () {
      expect(
        _hasVitD(
          applyEmittedBeneficialGate([
            _vitD(severity: Severity.contraindicated),
          ]),
        ),
        isTrue,
      );
    });
  });

  group('canary: wired into the product-detail filter (adds real coverage)', () {
    test('emitted beneficial suppresses a pair the const table does NOT cover', () {
      // Coenzyme Q10 / hypertension has NO positive entry in the const table
      // (which only covers magnesium / caffeine / licorice for hypertension),
      // so the Dart gate keeps it. The pipeline tags it direction=beneficial.
      // Only the emitted gate can drop it — proving the wiring adds coverage
      // beyond the Dart fallback (and will carry the load once the table goes).
      const coq10 = InteractionWarning(
        severity: Severity.monitor,
        evidenceLevel: EvidenceLevel.established,
        title: 'Coenzyme Q10 / hypertension',
        mechanism: 'CoQ10 modestly supports blood pressure.',
        management: 'Continue as directed.',
        conditionIds: ['hypertension'],
        ingredientName: 'Coenzyme Q10',
        direction: 'beneficial',
        materiality: 'presence',
      );
      final out = filterProductDetailWarningsForProfile(
        detailBlob: const <String, dynamic>{},
        warnings: [coq10],
        userConditions: const {'hypertension'},
        userDrugClasses: const {},
      );
      expect(
        out.any((w) => w.ingredientName == 'Coenzyme Q10'),
        isFalse,
        reason: 'beneficial monitor must not surface for a matching profile',
      );
    });

    test('a harmful warning for the same profile still surfaces', () {
      const coq10Harmful = InteractionWarning(
        severity: Severity.caution,
        evidenceLevel: EvidenceLevel.established,
        title: 'Coenzyme Q10 / hypertension',
        mechanism: 'x',
        management: 'y',
        conditionIds: ['hypertension'],
        ingredientName: 'Coenzyme Q10',
        direction: 'harmful',
        materiality: 'presence',
      );
      final out = filterProductDetailWarningsForProfile(
        detailBlob: const <String, dynamic>{},
        warnings: [coq10Harmful],
        userConditions: const {'hypertension'},
        userDrugClasses: const {},
      );
      expect(out.any((w) => w.ingredientName == 'Coenzyme Q10'), isTrue);
    });
  });
}
