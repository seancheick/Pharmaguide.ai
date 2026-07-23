// Adapter contract for the clinical-signal envelope (Workstream A, increment 2).
// Encodes the PM-locked semantics: a medication–nutrient relationship never maps
// to avoid/contraindicated; clinical_severity (ranking) and consumer_disposition
// (placement) are independent; source importance is preserved, not flattened;
// and signal identity is stable across re-eval / order / severity changes.

import 'package:flutter_test/flutter_test.dart';

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

InteractionResult _interaction({
  String id = 'rule_x',
  String a1 = 'Warfarin',
  String a2 = 'Fish Oil',
  Severity severity = Severity.avoid,
  Severity? curated,
  InteractionSource source = InteractionSource.pipeline,
  String? alertStyle,
}) => InteractionResult(
  id: id,
  type: InteractionType.drugSupplement,
  severity: severity,
  evidenceLevel: EvidenceLevel.established,
  agent1Name: a1,
  agent2Name: a2,
  mechanism: 'increases bleeding risk',
  management: 'monitor INR',
  doseDependant: false,
  doseThreshold: null,
  sourceUrls: const ['https://example.org/1'],
  source: source,
  alertStyle: alertStyle,
  curatedSeverity: curated,
);

DepletionMatch _depletion({
  String id = 'DEP_STATINS_COQ10',
  String drug = 'Statins',
  String drugClass = 'class:statins',
  String nutrient = 'CoQ10',
  String nutrientId = 'coenzyme_q10',
  String severity = 'significant',
  String type = 'depletion',
}) => DepletionMatch(
  depletionId: id,
  drugDisplayName: drug,
  drugClassId: drugClass,
  nutrientName: nutrient,
  nutrientCanonicalId: nutrientId,
  depletionType: type,
  severity: severity,
  mechanism: 'inhibits CoQ10 synthesis',
  recommendation: 'consider discussing with clinician',
  sourceUrls: const ['https://example.org/coq10'],
  clinicalImpact: 'lower CoQ10 levels in some people',
  coverageLevel: CoverageLevel.none,
);

MedicationProfileWarning _medProfile({
  String id = 'mpw_1',
  String ruleId = 'RULE_NSAID_PREGNANCY',
  String med = 'Ibuprofen',
  Severity severity = Severity.avoid,
}) => MedicationProfileWarning(
  id: id,
  ruleId: ruleId,
  medicationName: med,
  severity: severity,
  evidenceLevel: EvidenceLevel.established,
  headline: 'Avoid in third trimester',
  body: 'NSAIDs are not recommended late in pregnancy.',
  management: 'talk to your clinician',
  sourceUrls: const ['https://example.org/nsaid'],
);

NutrientStatus _nutrient({
  String canonicalId = 'vitamin_d',
  String display = 'Vitamin D',
  NutrientTier tier = NutrientTier.exceedsUl,
  double? pctOfUl = 250,
}) => NutrientStatus(
  total: NutrientTotal(
    canonicalId: canonicalId,
    displayName: display,
    totalAmount: 0,
    unit: 'mcg',
    contributions: const [],
  ),
  tier: tier,
  pctOfUl: pctOfUl,
  warning: 'Exceeds Upper Limit',
);

void main() {
  group('fromDepletion — medication–nutrient never escalates (PM-locked)', () {
    test('every importance maps to monitor + good_to_know, never avoid/contra', () {
      for (final importance in ['critical', 'significant', 'moderate', 'mild']) {
        final s = ClinicalSignal.fromDepletion(_depletion(severity: importance));
        expect(
          s.clinicalSeverity,
          Severity.monitor,
          reason: '"$importance" must cap at monitor for a monitoring relationship',
        );
        expect(s.clinicalSeverity, isNot(Severity.avoid));
        expect(s.clinicalSeverity, isNot(Severity.contraindicated));
        expect(s.clinicalSeverity, isNot(Severity.caution));
        expect(s.consumerDisposition, ConsumerDisposition.goodToKnow);
      }
    });

    test('preserves the raw source importance in the typed payload', () {
      final s = ClinicalSignal.fromDepletion(_depletion(severity: 'significant'));
      final payload = s.payload as MedicationNutrientPayload;
      expect(payload.relationshipImportance, 'significant');
      expect(payload.relationshipType, 'depletion');
      expect(payload.match.nutrientCanonicalId, 'coenzyme_q10');
    });

    test('different nutrient (same drug) → distinct signal ids', () {
      final coq10 = ClinicalSignal.fromDepletion(_depletion(nutrientId: 'coenzyme_q10'));
      final b12 = ClinicalSignal.fromDepletion(
        _depletion(id: 'DEP_STATINS_B12', nutrientId: 'vitamin_b12'),
      );
      expect(coq10.signalId, isNot(b12.signalId));
    });
  });

  group('fromInteraction — identity + severity', () {
    test('agent order does not change the signal id (A×B == B×A)', () {
      final ab = ClinicalSignal.fromInteraction(_interaction(a1: 'Warfarin', a2: 'Fish Oil'));
      final ba = ClinicalSignal.fromInteraction(_interaction(a1: 'Fish Oil', a2: 'Warfarin'));
      expect(ab.signalId, ba.signalId);
    });

    test('same rule + agents but changed severity keeps the same id', () {
      final avoid = ClinicalSignal.fromInteraction(_interaction(severity: Severity.avoid));
      final caution = ClinicalSignal.fromInteraction(_interaction(severity: Severity.caution));
      expect(avoid.signalId, caution.signalId);
      expect(avoid.clinicalSeverity, isNot(caution.clinicalSeverity));
    });

    test('heuristic ids collapse the stack-position index (same pair → same id)', () {
      final i1 = ClinicalSignal.fromInteraction(
        _interaction(id: 'STACK_BT_1', source: InteractionSource.stackEngine),
      );
      final i7 = ClinicalSignal.fromInteraction(
        _interaction(id: 'STACK_BT_7', source: InteractionSource.stackEngine),
      );
      expect(i1.signalId, i7.signalId);
      expect(i1.sourceRuleId, 'STACK_BT');
    });

    test('curated ids are NOT index-stripped (only stackEngine heuristics are)', () {
      final s = ClinicalSignal.fromInteraction(
        _interaction(id: 'curated_rule_9', source: InteractionSource.pipeline),
      );
      expect(s.sourceRuleId, 'curated_rule_9');
    });

    test('food advisory keeps true severity but is PLACED as good_to_know', () {
      // Displays informational; curatedSeverity holds the true weight; the
      // food_advisory_note style forces calm placement so it is never the
      // primary safety headline (the app can't confirm the food exposure).
      final s = ClinicalSignal.fromInteraction(
        _interaction(
          severity: Severity.informational,
          curated: Severity.avoid,
          alertStyle: 'food_advisory_note',
        ),
      );
      expect(s.clinicalSeverity, Severity.avoid, reason: 'true weight retained');
      expect(s.consumerDisposition, ConsumerDisposition.goodToKnow);
    });

    test('disposition is review for an actionable/hard interaction', () {
      final s = ClinicalSignal.fromInteraction(_interaction(severity: Severity.avoid));
      expect(s.consumerDisposition, ConsumerDisposition.review);
    });

    test('contraindicated interaction → block disposition', () {
      final s = ClinicalSignal.fromInteraction(
        _interaction(severity: Severity.contraindicated),
      );
      expect(s.consumerDisposition, ConsumerDisposition.block);
    });
  });

  group('fromNutrientStatus — cumulative exposure', () {
    test('over-UL below 200% → caution; at/above 200% → avoid', () {
      final mild = ClinicalSignal.fromNutrientStatus(_nutrient(pctOfUl: 150));
      final severe = ClinicalSignal.fromNutrientStatus(_nutrient(pctOfUl: 250));
      expect(mild.clinicalSeverity, Severity.caution);
      expect(severe.clinicalSeverity, Severity.avoid);
    });

    test('a safe tier → suppress disposition', () {
      final s = ClinicalSignal.fromNutrientStatus(
        _nutrient(tier: NutrientTier.adequate, pctOfUl: null),
      );
      expect(s.clinicalSeverity, Severity.safe);
      expect(s.consumerDisposition, ConsumerDisposition.suppress);
    });

    test('id is the nutrient alone (no sourceRuleId)', () {
      final s = ClinicalSignal.fromNutrientStatus(_nutrient(canonicalId: 'vitamin_d'));
      expect(s.sourceRuleId, isNull);
      expect(s.signalIdCanonical, 'pg_signal:v1:cumulativeExposure:vitamin_d');
    });
  });

  group('envelope invariants across all adapters', () {
    test('payload round-trips the original producer object', () {
      final r = _interaction();
      final s = ClinicalSignal.fromInteraction(r);
      expect(s.payload, isA<InteractionPayload>());
      expect((s.payload as InteractionPayload).result, same(r));
    });

    test('adapters over a producer result emit evaluationStatus.applicable', () {
      expect(ClinicalSignal.fromInteraction(_interaction()).evaluationStatus,
          EvaluationStatus.applicable);
      expect(ClinicalSignal.fromDepletion(_depletion()).evaluationStatus,
          EvaluationStatus.applicable);
      expect(ClinicalSignal.fromMedicationProfile(_medProfile()).evaluationStatus,
          EvaluationStatus.applicable);
      expect(ClinicalSignal.fromNutrientStatus(_nutrient()).evaluationStatus,
          EvaluationStatus.applicable);
    });

    test('every signal id is namespaced + versioned', () {
      final signals = [
        ClinicalSignal.fromInteraction(_interaction()),
        ClinicalSignal.fromDepletion(_depletion()),
        ClinicalSignal.fromMedicationProfile(_medProfile()),
        ClinicalSignal.fromNutrientStatus(_nutrient()),
      ];
      for (final s in signals) {
        expect(s.signalIdCanonical, startsWith('pg_signal:v1:'));
        expect(s.signalId, isNotEmpty);
        expect(s.copyId, isNotEmpty);
      }
    });
  });
}
