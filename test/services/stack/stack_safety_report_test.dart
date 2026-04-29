// Tests for StackSafetyReport (M4 §8.3) — the aggregator that fans
// every safety signal (M1 nutrient totals + M4 curated interactions +
// legacy heuristic checks) into the single object the safety UI
// renders from.
//
// We test the three exposed views:
//   - overallSeverity   (worst across all signals)
//   - severityCounts    (per-bucket counts)
//   - orderedWarnings   (most-severe-first, deterministic ordering
//                          by source bucket inside a tier)
//
// Plus the golden-path test the spec calls out: a stack with 3
// supplements + 2 medications produces the expected ordered warning
// list.
//
// Run:
//   flutter test test/services/stack/stack_safety_report_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

InteractionResult _interaction({
  required String id,
  required Severity severity,
  String agent1 = 'A',
  String agent2 = 'B',
  InteractionSource source = InteractionSource.pipeline,
  InteractionType type = InteractionType.supplementSupplement,
}) {
  return InteractionResult(
    id: id,
    type: type,
    severity: severity,
    evidenceLevel: EvidenceLevel.established,
    agent1Name: agent1,
    agent2Name: agent2,
    mechanism: 'mechanism for $id',
    management: 'manage $id',
    doseDependant: false,
    doseThreshold: null,
    sourceUrls: const <String>[],
    source: source,
  );
}

NutrientStatus _nutrient({
  required String canonicalId,
  required NutrientTier tier,
}) {
  return NutrientStatus(
    total: NutrientTotal(
      canonicalId: canonicalId,
      displayName: canonicalId,
      totalAmount: 100,
      unit: 'mg',
      contributions: const <NutrientContribution>[],
    ),
    tier: tier,
  );
}

void main() {
  group('StackSafetyReport', () {
    test('empty report has safe severity, zero counts, empty list', () {
      const report = StackSafetyReport();
      expect(report.isEmpty, isTrue);
      expect(report.overallSeverity, Severity.safe);
      expect(report.orderedWarnings, isEmpty);
      for (final s in Severity.values) {
        expect(report.severityCounts[s], 0);
      }
    });

    test('report with only safe-tier nutrients is still empty', () {
      final report = StackSafetyReport(
        nutrientStatuses: [
          _nutrient(canonicalId: 'b12', tier: NutrientTier.adequate),
          _nutrient(canonicalId: 'd', tier: NutrientTier.aboveTypical),
        ],
      );
      expect(report.isEmpty, isTrue);
      expect(report.overallSeverity, Severity.safe);
    });

    test('exceedsUl nutrient lifts overall severity to avoid', () {
      final report = StackSafetyReport(
        nutrientStatuses: [
          _nutrient(canonicalId: 'iron', tier: NutrientTier.exceedsUl),
        ],
      );
      expect(report.overallSeverity, Severity.avoid);
      expect(report.severityCounts[Severity.avoid], 1);
    });

    test('approachingUl nutrient lifts overall severity to caution', () {
      final report = StackSafetyReport(
        nutrientStatuses: [
          _nutrient(canonicalId: 'b6', tier: NutrientTier.approachingUl),
        ],
      );
      expect(report.overallSeverity, Severity.caution);
    });

    test('overall severity tracks the worst across all sources', () {
      final report = StackSafetyReport(
        stackInteractions: [_interaction(id: 'S1', severity: Severity.caution)],
        categoryWarnings: [_interaction(id: 'C1', severity: Severity.monitor)],
        medicationInteractions: [
          _interaction(id: 'M1', severity: Severity.contraindicated),
        ],
      );
      expect(report.overallSeverity, Severity.contraindicated);
    });

    test('severityCounts tally across all buckets', () {
      final report = StackSafetyReport(
        stackInteractions: [
          _interaction(id: 'S1', severity: Severity.caution),
          _interaction(id: 'S2', severity: Severity.caution),
        ],
        medicationInteractions: [
          _interaction(id: 'M1', severity: Severity.avoid),
        ],
        categoryWarnings: [_interaction(id: 'C1', severity: Severity.monitor)],
        nutrientStatuses: [
          _nutrient(canonicalId: 'iron', tier: NutrientTier.exceedsUl),
        ],
      );
      expect(report.severityCounts[Severity.avoid], 2); // M1 + iron
      expect(report.severityCounts[Severity.caution], 2); // S1+S2
      expect(report.severityCounts[Severity.monitor], 1); // C1
      expect(report.severityCounts[Severity.contraindicated], 0);
      expect(report.severityCounts[Severity.safe], 0);
    });

    test('orderedWarnings sorts by severity descending', () {
      final monitor = _interaction(id: 'M', severity: Severity.monitor);
      final caution = _interaction(id: 'C', severity: Severity.caution);
      final avoid = _interaction(id: 'A', severity: Severity.avoid);
      final report = StackSafetyReport(
        stackInteractions: [monitor, caution, avoid],
      );
      final ordered = report.orderedWarnings;
      expect(ordered, hasLength(3));
      expect((ordered[0] as InteractionResult).id, 'A');
      expect((ordered[1] as InteractionResult).id, 'C');
      expect((ordered[2] as InteractionResult).id, 'M');
    });

    test('inside same severity tier, medication interactions render before '
        'stack interactions, then category warnings, then nutrients', () {
      final med = _interaction(
        id: 'med',
        severity: Severity.caution,
        type: InteractionType.drugSupplement,
      );
      final stack = _interaction(id: 'stack', severity: Severity.caution);
      final cat = _interaction(
        id: 'cat',
        severity: Severity.caution,
        source: InteractionSource.stackEngine,
      );
      final nut = _nutrient(
        canonicalId: 'b6',
        tier: NutrientTier.approachingUl,
      );
      final report = StackSafetyReport(
        stackInteractions: [stack],
        medicationInteractions: [med],
        categoryWarnings: [cat],
        nutrientStatuses: [nut],
      );
      final ordered = report.orderedWarnings;
      expect(ordered, hasLength(4));
      expect((ordered[0] as InteractionResult).id, 'med');
      expect((ordered[1] as InteractionResult).id, 'stack');
      expect((ordered[2] as InteractionResult).id, 'cat');
      expect(ordered[3], isA<NutrientStatus>());
    });

    test('orderedWarnings preserves source-list order within a bucket', () {
      final s1 = _interaction(id: 's1', severity: Severity.caution);
      final s2 = _interaction(id: 's2', severity: Severity.caution);
      final s3 = _interaction(id: 's3', severity: Severity.caution);
      final report = StackSafetyReport(stackInteractions: [s1, s2, s3]);
      final ordered = report.orderedWarnings;
      expect((ordered[0] as InteractionResult).id, 's1');
      expect((ordered[1] as InteractionResult).id, 's2');
      expect((ordered[2] as InteractionResult).id, 's3');
    });

    test('safe-tier nutrients are not surfaced in orderedWarnings', () {
      final report = StackSafetyReport(
        nutrientStatuses: [
          _nutrient(canonicalId: 'iron', tier: NutrientTier.adequate),
          _nutrient(canonicalId: 'b6', tier: NutrientTier.exceedsUl),
        ],
      );
      final ordered = report.orderedWarnings;
      expect(ordered, hasLength(1));
      expect((ordered.single as NutrientStatus).total.canonicalId, 'b6');
    });

    test('GOLDEN: 3 sups + 2 meds yields expected ordered warnings', () {
      // Spec §8.6: "stack with 3 sups + 2 meds produces expected
      // ordered warnings". Build a representative report and lock the
      // exact order so future refactors don't accidentally reshuffle
      // the rendering contract.
      final medAvoid = _interaction(
        id: 'WARFARIN_VITK',
        severity: Severity.avoid,
        type: InteractionType.drugSupplement,
        agent1: 'Coumadin',
        agent2: 'Vitamin K2',
      );
      final medContra = _interaction(
        id: 'SSRI_SJW',
        severity: Severity.contraindicated,
        type: InteractionType.drugSupplement,
        agent1: 'Sertraline',
        agent2: 'St Johns Wort',
      );
      final stackCaution = _interaction(
        id: 'IRON_CALCIUM',
        severity: Severity.caution,
        agent1: 'Calcium 500mg',
        agent2: 'Iron 30mg',
      );
      final categoryMonitor = _interaction(
        id: 'STACK_DUP_0',
        severity: Severity.monitor,
        source: InteractionSource.stackEngine,
        agent1: 'Multi A',
        agent2: 'Multi B',
      );
      final ulIron = _nutrient(
        canonicalId: 'iron',
        tier: NutrientTier.exceedsUl,
      );

      final report = StackSafetyReport(
        stackInteractions: [stackCaution],
        medicationInteractions: [medAvoid, medContra],
        categoryWarnings: [categoryMonitor],
        nutrientStatuses: [ulIron],
      );

      expect(report.overallSeverity, Severity.contraindicated);
      expect(report.severityCounts[Severity.contraindicated], 1);
      expect(report.severityCounts[Severity.avoid], 2); // medAvoid + ulIron
      expect(report.severityCounts[Severity.caution], 1);
      expect(report.severityCounts[Severity.monitor], 1);

      final ordered = report.orderedWarnings;
      expect(ordered, hasLength(5));

      // contraindicated → medication interaction (med bucket sorts
      // before nutrients)
      expect((ordered[0] as InteractionResult).id, 'SSRI_SJW');

      // avoid tier — medication first, then nutrient
      expect((ordered[1] as InteractionResult).id, 'WARFARIN_VITK');
      expect((ordered[2] as NutrientStatus).total.canonicalId, 'iron');

      // caution → stack pair interaction
      expect((ordered[3] as InteractionResult).id, 'IRON_CALCIUM');

      // monitor → category heuristic
      expect((ordered[4] as InteractionResult).id, 'STACK_DUP_0');
    });

    test('isEmpty is true when only flagged-source lists are empty', () {
      final report = StackSafetyReport(
        nutrientStatuses: [
          _nutrient(canonicalId: 'b6', tier: NutrientTier.adequate),
        ],
      );
      expect(report.isEmpty, isTrue);
    });

    test('isEmpty becomes false when any flagged signal exists', () {
      final report = StackSafetyReport(
        categoryWarnings: [_interaction(id: 'C', severity: Severity.monitor)],
      );
      expect(report.isEmpty, isFalse);
    });
  });
}
