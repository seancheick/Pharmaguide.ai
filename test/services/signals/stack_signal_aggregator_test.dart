// Characterization contract for the typed StackSafetyReport → ClinicalSignal
// aggregation (Workstream A, increment 3). Proves membership matches
// orderedWarnings, the bucket priority is preserved, only warn-worthy nutrients
// are included, and the ONE intentional change — ranking on true (effective)
// severity — actually reorders a food advisory above a lower display-severity
// item, closing the orderedWarnings seam.

import 'package:flutter_test/flutter_test.dart';

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
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

void main() {
  test('every ordered warning becomes exactly one signal (same membership)', () {
    final report = StackSafetyReport(
      medicationInteractions: [_ix(id: 'm1', severity: Severity.avoid)],
      stackInteractions: [_ix(id: 's1', severity: Severity.caution)],
      nutrientStatuses: [_nut()],
    );
    expect(orderedSignalsFrom(report).length, report.orderedWarnings.length);
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
    final cumulative = orderedSignalsFrom(report)
        .where((s) => s.family == SignalFamily.cumulativeExposure)
        .toList();
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

  test('empty report yields no signals', () {
    expect(orderedSignalsFrom(const StackSafetyReport()), isEmpty);
  });
}
