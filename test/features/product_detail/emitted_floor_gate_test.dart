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
}) {
  return InteractionWarning(
    severity: severity,
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

    test('beneficial below floor → fires (only harmful is suppressible)', () {
      expect(
        _hasNiacin(applyEmittedFloorGate(
          [_niacin(doseFloorStatus: 'below', direction: 'beneficial')],
        )),
        isTrue,
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
}
