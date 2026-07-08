import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/product_detail_helpers.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

InteractionWarning _niacin({
  required String? doseFloorStatus,
  String? direction = 'harmful',
  String? materiality = 'dose_dependent',
  Severity severity = Severity.caution,
  String? severityRaw,
}) {
  return InteractionWarning(
    severity: severity,
    severityRaw: severityRaw ?? severity.name,
    evidenceLevel: EvidenceLevel.established,
    title: 'Niacin / diabetes',
    mechanism: 'High-dose niacin raises glucose.',
    management: 'Monitor glucose.',
    conditionIds: const ['diabetes'],
    ingredientName: 'Niacin',
    direction: direction,
    materiality: materiality,
    doseFloorStatus: doseFloorStatus,
  );
}

bool _hasNiacin(List<InteractionWarning> ws) =>
    ws.any((w) => w.ingredientName == 'Niacin');

void main() {
  group('applyEmittedFloorGate — narrow suppression predicate (G3)', () {
    test('below floor + harmful + dose_dependent → suppressed', () {
      expect(applyEmittedFloorGate([_niacin(doseFloorStatus: 'below')]), isEmpty);
    });

    test('at_or_above floor → fires', () {
      expect(_hasNiacin(applyEmittedFloorGate([_niacin(doseFloorStatus: 'at_or_above')])), isTrue);
    });

    test('null floor status (niacinamide / unknown dose) → fires (fail open)', () {
      expect(_hasNiacin(applyEmittedFloorGate([_niacin(doseFloorStatus: null)])), isTrue);
    });

    test('hard override (avoid) below floor → still fires', () {
      expect(
        _hasNiacin(applyEmittedFloorGate(
          [_niacin(doseFloorStatus: 'below', severity: Severity.avoid)],
        )),
        isTrue,
      );
    });

    test('unknown / drifted severity string below floor → fires (fail safe)', () {
      // Severity.fromString coerces unknown tokens to caution; the raw-string
      // fail-safe must keep a possibly-serious drifted row visible.
      expect(
        _hasNiacin(applyEmittedFloorGate(
          [_niacin(doseFloorStatus: 'below', severityRaw: 'severe')],
        )),
        isTrue,
      );
    });

    test('missing severity (empty raw) below floor → fires (fail safe)', () {
      expect(
        _hasNiacin(applyEmittedFloorGate(
          [_niacin(doseFloorStatus: 'below', severityRaw: '')],
        )),
        isTrue,
      );
    });

    test('beneficial below floor → fires (only harmful is suppressible)', () {
      expect(
        _hasNiacin(applyEmittedFloorGate(
          [_niacin(doseFloorStatus: 'below', direction: 'beneficial')],
        )),
        isTrue,
      );
    });

    test('neutral below floor → suppressed for dose-dependent high-dose guidance', () {
      expect(
        applyEmittedFloorGate(
          [_niacin(doseFloorStatus: 'below', direction: 'neutral')],
        ),
        isEmpty,
      );
    });

    test('form mismatch → suppressed for dose-dependent high-dose guidance', () {
      expect(
        applyEmittedFloorGate(
          [_niacin(doseFloorStatus: 'form_mismatch')],
        ),
        isEmpty,
      );
    });

    test('presence materiality below floor → fires (never dose-suppressed)', () {
      expect(
        _hasNiacin(applyEmittedFloorGate(
          [_niacin(doseFloorStatus: 'below', materiality: 'presence')],
        )),
        isTrue,
      );
    });

    test('legacy warning without the new fields → fires', () {
      const legacy = InteractionWarning(
        severity: Severity.caution,
        evidenceLevel: EvidenceLevel.probable,
        title: 'Legacy warning',
        mechanism: 'x',
        management: 'y',
      );
      expect(applyEmittedFloorGate([legacy]).length, 1);
    });
  });

  group('canary: end-to-end through the product-detail filter (G2)', () {
    test('below-floor niacin dropped even for a matching diabetes profile', () {
      final out = filterProductDetailWarningsForProfile(
        detailBlob: const <String, dynamic>{},
        warnings: [_niacin(doseFloorStatus: 'below')],
        userConditions: const {'diabetes'},
        userDrugClasses: const {},
      );
      expect(_hasNiacin(out), isFalse, reason: 'below-floor row must not be promoted back');
    });

    test('at_or_above niacin still shown for a diabetes profile', () {
      final out = filterProductDetailWarningsForProfile(
        detailBlob: const <String, dynamic>{},
        warnings: [_niacin(doseFloorStatus: 'at_or_above')],
        userConditions: const {'diabetes'},
        userDrugClasses: const {},
      );
      expect(_hasNiacin(out), isTrue);
    });

    test('missing floor status still fires for a diabetes profile', () {
      final out = filterProductDetailWarningsForProfile(
        detailBlob: const <String, dynamic>{},
        warnings: [_niacin(doseFloorStatus: null)],
        userConditions: const {'diabetes'},
        userDrugClasses: const {},
      );
      expect(_hasNiacin(out), isTrue);
    });
  });

  group('dedupe vs floor gate (D1 guard — adversarial audit)', () {
    test('twins differing only in doseFloorStatus are not collapsed', () {
      // Same headline/body/conditions => identical legacy dedupe key. The
      // suppressible "below" twin must not swallow the firing "null" twin
      // before the floor gate runs (dedupe precedes the gate).
      final deduped = InteractionWarning.dedupe([
        _niacin(doseFloorStatus: 'below'),
        _niacin(doseFloorStatus: null),
      ]);
      expect(deduped.length, 2, reason: 'floor fields must be in the dedupe key');
    });

    test('true identical duplicates still collapse', () {
      final deduped = InteractionWarning.dedupe([
        _niacin(doseFloorStatus: 'below'),
        _niacin(doseFloorStatus: 'below'),
      ]);
      expect(deduped.length, 1);
    });
  });
}
