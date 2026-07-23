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

  test('food advisory ranks by TRUE severity, fixing the display-downgrade seam', () {
    // Displays informational but is truly avoid (curatedSeverity).
    final foodAdvisory = _ix(
      id: 'm1',
      severity: Severity.informational,
      curated: Severity.avoid,
    );
    final plainCaution = _ix(id: 's1', severity: Severity.caution);
    final report = StackSafetyReport(
      medicationInteractions: [foodAdvisory],
      stackInteractions: [plainCaution],
    );

    // Old path ranks on display severity: caution (3) > informational (1).
    expect((report.orderedWarnings.first as InteractionResult).id, 's1');

    // New path ranks on effective severity: avoid (4) > caution (3).
    final signals = orderedSignalsFrom(report);
    expect(signals.first.clinicalSeverity, Severity.avoid);
    expect((signals.first.payload as InteractionPayload).result.id, 'm1');
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

  test('empty report yields no signals', () {
    expect(orderedSignalsFrom(const StackSafetyReport()), isEmpty);
  });
}
