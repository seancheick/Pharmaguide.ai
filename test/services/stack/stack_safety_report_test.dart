// Tests for StackSafetyReport (M4 §8.3) — the aggregator that fans
// every safety signal (M1 nutrient totals + M4 curated interactions +
// legacy heuristic checks) into the single object the safety UI
// renders from.
//
// We test the three exposed views:
//   - overallSeverity   (worst across all signals)
//   - severityCounts    (per-bucket counts)
//
// Rendering order + the golden-path ordering test moved to the signals
// layer (test/services/signals/stack_signal_aggregator_test.dart) when
// the legacy orderedWarnings getter was removed.
//
// Run:
//   flutter test test/services/stack/stack_safety_report_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
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
  double totalAmount = 100,
  String unit = 'mg',
  double? ul,
  double? pctOfUl,
  List<NutrientContribution> contributions = const <NutrientContribution>[],
  bool ulIsFallback = false,
}) {
  return NutrientStatus(
    total: NutrientTotal(
      canonicalId: canonicalId,
      displayName: canonicalId,
      totalAmount: totalAmount,
      unit: unit,
      contributions: contributions,
    ),
    tier: tier,
    ul: ul,
    pctOfUl: pctOfUl,
    ulIsFallback: ulIsFallback,
  );
}

MedicationProfileWarning _profileWarning({
  required String id,
  required Severity severity,
  String medicationName = 'Motrin',
}) {
  return MedicationProfileWarning(
    id: id,
    ruleId: id,
    medicationName: medicationName,
    severity: severity,
    evidenceLevel: EvidenceLevel.established,
    headline: 'Review NSAID use in pregnancy',
    body: 'NSAID use needs profile review.',
    management: 'Check with your clinician.',
    sourceUrls: const <String>[],
  );
}

void main() {
  group('StackSafetyReport', () {
    test('empty report has safe severity, zero counts, empty list', () {
      const report = StackSafetyReport();
      expect(report.isEmpty, isTrue);
      expect(report.overallSeverity, Severity.safe);
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

    test('125% UL nutrient is a caution, not an avoid-level event', () {
      final report = StackSafetyReport(
        nutrientStatuses: [
          _nutrient(
            canonicalId: 'vitamin_d',
            tier: NutrientTier.exceedsUl,
            totalAmount: 125,
            unit: 'mcg',
            ul: 100,
            pctOfUl: 125,
          ),
        ],
      );
      expect(report.overallSeverity, Severity.caution);
      expect(report.severityCounts[Severity.caution], 1);
      expect(
        StackSafetyReport.nutrientUpperLimitSummary(
          report.nutrientStatuses.single,
        ),
        contains('125 mcg/day'),
      );
    });

    test('a very high UL breach retains avoid-level severity', () {
      final report = StackSafetyReport(
        nutrientStatuses: [
          _nutrient(
            canonicalId: 'iron',
            tier: NutrientTier.exceedsUl,
            pctOfUl: 200,
          ),
        ],
      );
      expect(report.overallSeverity, Severity.avoid);
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

    test('medication-profile warnings contribute counts and emptiness', () {
      final report = StackSafetyReport(
        medicationProfileWarnings: [
          _profileWarning(id: 'pregnancy_nsaid', severity: Severity.caution),
        ],
      );

      expect(report.isEmpty, isFalse);
      expect(report.overallSeverity, Severity.caution);
      expect(report.severityCounts[Severity.caution], 1);
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
