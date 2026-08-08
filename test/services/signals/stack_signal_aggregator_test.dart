// Contract for the typed StackSafetyReport → ClinicalSignal aggregation
// (Workstream A). Owns the rendering-order coverage (bucket priority + golden)
// now that StackSafetyReport.orderedWarnings is gone: disposition-first ranking,
// warn-worthy-only nutrients, suppress exclusion, and the food-advisory fix.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

InteractionResult _ix({
  String id = 'r',
  String a1 = 'A',
  String a2 = 'B',
  Severity severity = Severity.caution,
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
  mechanism: 'm',
  management: 'g',
  doseDependant: false,
  doseThreshold: null,
  sourceUrls: const [],
  source: source,
  alertStyle: alertStyle,
  curatedSeverity: curated,
);

NutrientStatus _nut({
  String id = 'vitamin_d',
  NutrientTier tier = NutrientTier.exceedsUl,
  double? pctOfUl = 250,
}) => NutrientStatus(
  total: NutrientTotal(
    canonicalId: id,
    displayName: id,
    totalAmount: 0,
    unit: 'mcg',
    contributions: const [],
  ),
  tier: tier,
  pctOfUl: pctOfUl,
  warning: 'w',
);

MedicationProfileWarning _mpw({
  required String id,
  Severity severity = Severity.caution,
}) => MedicationProfileWarning(
  id: id,
  ruleId: id,
  medicationName: 'Med',
  severity: severity,
  evidenceLevel: EvidenceLevel.established,
  headline: 'headline',
  body: 'body',
  management: 'manage',
  sourceUrls: const [],
);

DepletionMatch _depletion() => const DepletionMatch(
  depletionId: 'DEP_METFORMIN_B12',
  drugDisplayName: 'Metformin',
  drugClassId: 'class:biguanides',
  nutrientName: 'Vitamin B12',
  nutrientCanonicalId: 'vitamin_b12',
  depletionType: 'depletion',
  severity: 'significant',
  mechanism: 'May reduce vitamin B12 absorption over time.',
  recommendation: 'Discuss monitoring with your clinician.',
  sourceUrls: ['https://pubmed.ncbi.nlm.nih.gov/20488910/'],
  coverageLevel: CoverageLevel.none,
);

void main() {
  test('every flagged item becomes exactly one signal', () {
    final report = StackSafetyReport(
      medicationInteractions: [_ix(id: 'm1', severity: Severity.avoid)],
      stackInteractions: [_ix(id: 's1', severity: Severity.caution)],
      nutrientStatuses: [_nut()],
    );
    expect(orderedSignalsFrom(report), hasLength(3));
  });

  test('ranks by clinical severity, then bucket priority', () {
    final report = StackSafetyReport(
      stackInteractions: [_ix(id: 's1', severity: Severity.monitor)],
      medicationPairInteractions: [_ix(id: 'p1', severity: Severity.avoid)],
    );
    final signals = orderedSignalsFrom(report);
    expect(signals.first.clinicalSeverity, Severity.avoid);
    expect(signals.last.clinicalSeverity, Severity.monitor);
  });

  test('food advisory (good_to_know) never displaces a review concern', () {
    // Truly avoid (curatedSeverity) but a food advisory → good_to_know.
    final foodAdvisory = _ix(
      id: 'm1',
      severity: Severity.informational,
      curated: Severity.avoid,
      alertStyle: 'food_advisory_note',
    );
    final plainCaution = _ix(id: 's1', severity: Severity.caution); // → review
    final report = StackSafetyReport(
      medicationInteractions: [foodAdvisory],
      stackInteractions: [plainCaution],
    );

    final signals = orderedSignalsFrom(report);
    // Disposition-first: the review caution outranks the good_to_know advisory
    // even though the advisory's clinical severity (avoid) is higher.
    expect(signals.first.consumerDisposition, ConsumerDisposition.review);
    expect((signals.first.payload as InteractionPayload).result.id, 's1');
    // The advisory still appears — with its true severity — just not first.
    expect(signals.last.consumerDisposition, ConsumerDisposition.goodToKnow);
    expect(signals.last.clinicalSeverity, Severity.avoid);
  });

  test('maps families correctly', () {
    final report = StackSafetyReport(
      medicationInteractions: [_ix(id: 'm1')],
      nutrientStatuses: [_nut()],
    );
    final families = orderedSignalsFrom(report).map((s) => s.family).toSet();
    expect(families, contains(SignalFamily.pairwiseInteraction));
    expect(families, contains(SignalFamily.cumulativeExposure));
  });

  test('complete aggregation includes medication–nutrient signals once', () {
    final signals = allClinicalSignalsFrom(
      report: const StackSafetyReport(),
      medicationNutrientMatches: [_depletion()],
    );

    expect(signals, hasLength(1));
    expect(signals.single.family, SignalFamily.medicationNutrient);
    expect(signals.single.consumerDisposition, ConsumerDisposition.goodToKnow);
    expect(signals.single.signalId, isNotEmpty);
  });

  test('interaction and medication/nutrient guidance keep distinct labels', () {
    final signals = allClinicalSignalsFrom(
      report: StackSafetyReport(
        medicationInteractions: [
          _ix(id: 'WARFARIN_E', a1: 'Warfarin', a2: 'Vitamin E'),
        ],
      ),
      medicationNutrientMatches: [
        const DepletionMatch(
          depletionId: 'WARFARIN_VITAMIN_K',
          drugDisplayName: 'Warfarin',
          drugClassId: 'class:anticoagulants',
          nutrientName: 'Vitamin K',
          nutrientCanonicalId: 'vitamin_k',
          depletionType: 'functional_antagonism',
          severity: 'significant',
          mechanism: 'Consistency matters.',
          recommendation: 'Keep intake consistent.',
          sourceUrls: [],
          coverageLevel: CoverageLevel.none,
        ),
      ],
    );

    expect(clinicalSignalKindLabel(signals[0]), 'Supplement interaction');
    expect(clinicalSignalKindLabel(signals[1]), 'Medication/nutrient guidance');
  });

  test('mixed report includes dose thresholds in the shared ordering', () {
    final signals = orderedSignalsFrom(
      StackSafetyReport(
        medicationInteractions: [_ix(id: 'med')],
        nutrientStatuses: [_nut()],
      ),
      doseThresholdAlerts: const [
        StackDoseThresholdAlert(
          conditionId: 'pregnancy',
          canonicalId: 'caffeine',
          displayName: 'Caffeine',
          totalValue: 240,
          unit: 'mg',
          thresholdValue: 200,
          thresholdUnit: 'mg',
          contributions: [],
        ),
      ],
    );

    expect(signals, hasLength(3));
    expect(
      signals.map((signal) => signal.family),
      containsAll([
        SignalFamily.pairwiseInteraction,
        SignalFamily.cumulativeExposure,
        SignalFamily.doseThreshold,
      ]),
    );
  });

  test('unknown authored dose disposition fails visible, never suppressed', () {
    final signals = orderedSignalsFrom(
      const StackSafetyReport(),
      doseThresholdAlerts: const [
        StackDoseThresholdAlert(
          conditionId: 'pregnancy',
          canonicalId: 'caffeine',
          displayName: 'Caffeine',
          totalValue: 240,
          unit: 'mg',
          thresholdValue: 200,
          thresholdUnit: 'mg',
          contributions: [],
          consumerDisposition: 'not_a_real_disposition',
        ),
      ],
    );

    expect(signals, hasLength(1));
    expect(
      signals.single.consumerDisposition,
      ConsumerDisposition.review,
      reason:
          'the alert already counts toward the tier, so it must stay visible '
          'in the review universe',
    );
  });

  test('lifecycle persistence consumes the same dose-threshold signals', () {
    final source = File(
      'lib/features/history/providers/clinical_signal_lifecycle_provider.dart',
    ).readAsStringSync();
    expect(source, contains('stackDoseThresholdAlertsProvider'));
    expect(source, contains('doseThresholdAlerts: doseThresholdAlerts'));
  });

  test('only warn-worthy nutrients are included', () {
    final report = StackSafetyReport(
      nutrientStatuses: [
        _nut(id: 'calcium', tier: NutrientTier.adequate, pctOfUl: null),
        _nut(id: 'iron', tier: NutrientTier.exceedsUl, pctOfUl: 250),
      ],
    );
    final cumulative = orderedSignalsFrom(
      report,
    ).where((s) => s.family == SignalFamily.cumulativeExposure).toList();
    expect(cumulative.length, 1);
  });

  test('a block (contraindicated) signal wins the headline', () {
    final report = StackSafetyReport(
      medicationPairInteractions: [
        _ix(id: 'p1', severity: Severity.contraindicated),
      ],
      stackInteractions: [_ix(id: 's1', severity: Severity.avoid)],
    );
    final signals = orderedSignalsFrom(report);
    expect(signals.first.consumerDisposition, ConsumerDisposition.block);
    expect((signals.first.payload as InteractionPayload).result.id, 'p1');
  });

  test('suppress-disposition signals are excluded', () {
    final report = StackSafetyReport(
      stackInteractions: [
        _ix(id: 's1', severity: Severity.safe), // → suppress, excluded
        _ix(id: 's2', severity: Severity.caution), // → review
      ],
    );
    final signals = orderedSignalsFrom(report);
    expect(signals.length, 1);
    expect((signals.first.payload as InteractionPayload).result.id, 's2');
  });

  test('within one disposition + severity, buckets render in risk order', () {
    final report = StackSafetyReport(
      medicationPairInteractions: [
        _ix(id: 'med_pair', severity: Severity.caution),
      ],
      medicationProfileWarnings: [
        _mpw(id: 'med_profile', severity: Severity.caution),
      ],
      medicationInteractions: [_ix(id: 'med', severity: Severity.caution)],
      stackInteractions: [_ix(id: 'stack', severity: Severity.caution)],
      categoryWarnings: [
        _ix(
          id: 'cat',
          severity: Severity.caution,
          source: InteractionSource.stackEngine,
        ),
      ],
      nutrientStatuses: [_nut(id: 'b6', tier: NutrientTier.approachingUl)],
    );
    final signals = orderedSignalsFrom(report);
    expect(signals, hasLength(6));
    expect((signals[0].payload as InteractionPayload).result.id, 'med_pair');
    expect(
      (signals[1].payload as MedicationProfilePayload).warning.id,
      'med_profile',
    );
    expect((signals[2].payload as InteractionPayload).result.id, 'med');
    expect((signals[3].payload as InteractionPayload).result.id, 'stack');
    expect((signals[4].payload as InteractionPayload).result.id, 'cat');
    expect(signals[5].family, SignalFamily.cumulativeExposure);
  });

  test('GOLDEN: mixed-severity report locks the ordering contract', () {
    final report = StackSafetyReport(
      stackInteractions: [_ix(id: 'IRON_CALCIUM', severity: Severity.caution)],
      medicationInteractions: [
        _ix(id: 'WARFARIN_VITK', severity: Severity.avoid),
        _ix(id: 'SSRI_SJW', severity: Severity.contraindicated),
      ],
      categoryWarnings: [
        _ix(
          id: 'STACK_DUP_0',
          severity: Severity.monitor,
          source: InteractionSource.stackEngine,
        ),
      ],
      nutrientStatuses: [
        _nut(id: 'iron', tier: NutrientTier.exceedsUl, pctOfUl: 250),
      ],
    );
    final signals = orderedSignalsFrom(report);
    expect(signals, hasLength(5));
    // block (contraindicated) first.
    expect((signals[0].payload as InteractionPayload).result.id, 'SSRI_SJW');
    // avoid tier: medication before nutrient.
    expect(
      (signals[1].payload as InteractionPayload).result.id,
      'WARFARIN_VITK',
    );
    expect(signals[2].family, SignalFamily.cumulativeExposure);
    // caution → stack pair, then monitor → category.
    expect(
      (signals[3].payload as InteractionPayload).result.id,
      'IRON_CALCIUM',
    );
    expect((signals[4].payload as InteractionPayload).result.id, 'STACK_DUP_0');
  });

  test('empty report yields no signals', () {
    expect(orderedSignalsFrom(const StackSafetyReport()), isEmpty);
  });
}
