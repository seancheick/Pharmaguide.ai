import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/product_detail_helpers.dart';
import 'package:pharmaguide/services/warnings/condition_gate.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

InteractionWarning _niacin({
  required String? doseFloorStatus,
  DoseDecision? doseDecision,
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
    doseDecision: doseDecision,
  );
}

bool _hasNiacin(List<InteractionWarning> ws) =>
    ws.any((w) => w.ingredientName == 'Niacin');

void main() {
  group('three-axis dose decision gate', () {
    test('authored suppress disposition hides a below-threshold result', () {
      final warning = _niacin(
        doseFloorStatus: null,
        doseDecision: const DoseDecision(
          clinicalSeverity: 'caution',
          evaluationStatus: 'below_threshold',
          consumerDisposition: 'suppress',
        ),
      );
      expect(applyConsumerDispositionGate([warning]), isEmpty);
    });

    test('consumer disposition is independent from hard clinical severity', () {
      final warning = _niacin(
        doseFloorStatus: null,
        severity: Severity.avoid,
        doseDecision: const DoseDecision(
          clinicalSeverity: 'avoid',
          evaluationStatus: 'below_threshold',
          consumerDisposition: 'suppress',
        ),
      );
      expect(applyConsumerDispositionGate([warning]), isEmpty);
    });

    test('review and block dispositions remain visible', () {
      for (final disposition in const ['review', 'block']) {
        final warning = _niacin(
          doseFloorStatus: null,
          doseDecision: DoseDecision(
            clinicalSeverity: 'caution',
            evaluationStatus: 'above_threshold',
            consumerDisposition: disposition,
          ),
        );
        expect(applyConsumerDispositionGate([warning]), [warning]);
      }
    });

    test('unknown disposition fails visible instead of silently hiding', () {
      final warning = _niacin(
        doseFloorStatus: null,
        doseDecision: const DoseDecision(
          clinicalSeverity: 'caution',
          evaluationStatus: 'below_threshold',
          consumerDisposition: 'maybe',
        ),
      );
      expect(applyConsumerDispositionGate([warning]), [warning]);
    });

    test('parses compact pipeline dose decision', () {
      final warning = InteractionWarning.fromJson({
        'severity': 'caution',
        'title': 'Niacin / statins',
        'ingredient_name': 'Niacin',
        'ingredient_canonical_id': 'niacin',
        'dose_decision': {
          'clinical_severity': 'caution',
          'evaluation_status': 'below_threshold',
          'consumer_disposition': 'suppress',
          'evaluated_daily_amount': 20,
          'evaluated_unit': 'mg',
          'normalized_per_serving_amount': 20,
          'normalized_per_serving_unit': 'mg',
          'evaluated_serving_multiplier': 1,
          'threshold': 1000,
          'threshold_unit': 'mg',
          'comparator': '>=',
          'decision_rule': {
            'consumer_disposition_if_met': 'review',
            'consumer_disposition_if_not_met': 'suppress',
            'amount_missing_disposition': 'suppress',
            'unknown_form_disposition': 'suppress',
            'conversion_failure_policy': 'release_block',
          },
        },
      });

      expect(warning.doseDecision?.consumerDisposition, 'suppress');
      expect(warning.ingredientCanonicalId, 'niacin');
      expect(warning.doseDecision?.evaluatedDailyAmount, 20);
      expect(warning.doseDecision?.threshold, 1000);
      expect(
        warning.doseDecision?.decisionRule?.consumerDispositionIfMet,
        'review',
      );
      expect(
        warning.doseDecision?.decisionRule?.amountMissingDisposition,
        'suppress',
      );
      expect(
        warning.doseDecision?.decisionRule?.unknownFormDisposition,
        'suppress',
      );
      expect(
        warning.doseDecision?.decisionRule?.conversionFailurePolicy,
        'release_block',
      );
    });
  });

  group('applyEmittedFloorGate — narrow suppression predicate (G3)', () {
    test('below floor + harmful + dose_dependent → suppressed', () {
      expect(
        applyEmittedFloorGate([_niacin(doseFloorStatus: 'below')]),
        isEmpty,
      );
    });

    test('at_or_above floor → fires', () {
      expect(
        _hasNiacin(
          applyEmittedFloorGate([_niacin(doseFloorStatus: 'at_or_above')]),
        ),
        isTrue,
      );
    });

    test(
      'null floor status (niacinamide / unknown dose) → fires (fail open)',
      () {
        expect(
          _hasNiacin(applyEmittedFloorGate([_niacin(doseFloorStatus: null)])),
          isTrue,
        );
      },
    );

    test('hard override (avoid) below floor → still fires', () {
      expect(
        _hasNiacin(
          applyEmittedFloorGate([
            _niacin(doseFloorStatus: 'below', severity: Severity.avoid),
          ]),
        ),
        isTrue,
      );
    });

    test(
      'unknown / drifted severity string below floor → fires (fail safe)',
      () {
        // Severity.fromString coerces unknown tokens to caution; the raw-string
        // fail-safe must keep a possibly-serious drifted row visible.
        expect(
          _hasNiacin(
            applyEmittedFloorGate([
              _niacin(doseFloorStatus: 'below', severityRaw: 'severe'),
            ]),
          ),
          isTrue,
        );
      },
    );

    test('missing severity (empty raw) below floor → fires (fail safe)', () {
      expect(
        _hasNiacin(
          applyEmittedFloorGate([
            _niacin(doseFloorStatus: 'below', severityRaw: ''),
          ]),
        ),
        isTrue,
      );
    });

    test('beneficial below floor → fires (only harmful is suppressible)', () {
      expect(
        _hasNiacin(
          applyEmittedFloorGate([
            _niacin(doseFloorStatus: 'below', direction: 'beneficial'),
          ]),
        ),
        isTrue,
      );
    });

    test(
      'neutral below floor → suppressed for dose-dependent high-dose guidance',
      () {
        expect(
          applyEmittedFloorGate([
            _niacin(doseFloorStatus: 'below', direction: 'neutral'),
          ]),
          isEmpty,
        );
      },
    );

    test(
      'form mismatch → suppressed for dose-dependent high-dose guidance',
      () {
        expect(
          applyEmittedFloorGate([_niacin(doseFloorStatus: 'form_mismatch')]),
          isEmpty,
        );
      },
    );

    test(
      'presence materiality below floor → fires (never dose-suppressed)',
      () {
        expect(
          _hasNiacin(
            applyEmittedFloorGate([
              _niacin(doseFloorStatus: 'below', materiality: 'presence'),
            ]),
          ),
          isTrue,
        );
      },
    );

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
    test(
      'new-contract suppress result cannot be revived by a matching profile',
      () {
        final out = filterProductDetailWarningsForProfile(
          detailBlob: const <String, dynamic>{},
          warnings: [
            _niacin(
              doseFloorStatus: null,
              severity: Severity.avoid,
              doseDecision: const DoseDecision(
                clinicalSeverity: 'avoid',
                evaluationStatus: 'below_threshold',
                consumerDisposition: 'suppress',
              ),
            ),
          ],
          userConditions: const {'diabetes'},
          userDrugClasses: const {},
        );
        expect(out, isEmpty);
      },
    );

    test('below-floor niacin dropped even for a matching diabetes profile', () {
      final out = filterProductDetailWarningsForProfile(
        detailBlob: const <String, dynamic>{},
        warnings: [_niacin(doseFloorStatus: 'below')],
        userConditions: const {'diabetes'},
        userDrugClasses: const {},
      );
      expect(
        _hasNiacin(out),
        isFalse,
        reason: 'below-floor row must not be promoted back',
      );
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

    test(
      'suppressed untagged warning with unknown severity fires fail safe',
      () {
        const warning = InteractionWarning(
          severity: Severity.caution,
          severityRaw: 'severe',
          evidenceLevel: EvidenceLevel.established,
          title: 'Unknown severity token',
          mechanism: 'x',
          management: 'y',
          displayModeDefault: 'suppress',
        );
        final out = filterProductDetailWarningsForProfile(
          detailBlob: const <String, dynamic>{},
          warnings: const [warning],
          userConditions: const {},
          userDrugClasses: const {},
        );
        expect(out, const [warning]);
      },
    );

    test('known lower severity still respects suppress display mode', () {
      const warning = InteractionWarning(
        severity: Severity.caution,
        severityRaw: 'caution',
        evidenceLevel: EvidenceLevel.established,
        title: 'Known suppressed warning',
        mechanism: 'x',
        management: 'y',
        displayModeDefault: 'suppress',
      );
      final out = filterProductDetailWarningsForProfile(
        detailBlob: const <String, dynamic>{},
        warnings: const [warning],
        userConditions: const {},
        userDrugClasses: const {},
      );
      expect(out, isEmpty);
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
      expect(
        deduped.length,
        2,
        reason: 'floor fields must be in the dedupe key',
      );
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
