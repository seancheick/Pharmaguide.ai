// Contract for the typed StackSafetyReport → ClinicalSignal aggregation
// (Workstream A). Owns the rendering-order coverage (bucket priority + golden)
// now that StackSafetyReport.orderedWarnings is gone: disposition-first ranking,
// warn-worthy-only nutrients, suppress exclusion, and the food-advisory fix.

import 'package:flutter_test/flutter_test.dart';

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
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
