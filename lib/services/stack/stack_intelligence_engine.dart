// StackIntelligenceEngine — facade that composes existing stack reports
// into a single [StackIntelligence] verdict.
//
// The engine never duplicates logic from `StackSafetyScorer`,
// `StackInteractionChecker`, or `StackNutrientAggregator`. It only reads
// counts/flags off the pre-built reports and feeds them into
// `StackIntelligence.deriveTier`, then assembles the actionable
// `StackIssue` list.
//
// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track B, B2.

import 'package:flutter/foundation.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/synergy_result.dart' as core_models;
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/services/signals/clinical_signal_envelope.dart';
import 'package:pharmaguide/services/signals/stack_signal_aggregator.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/stack_safety_scorer.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

/// One shared Stack Health interpretation for every consumer surface.
///
/// [intelligence] owns the tier and clinical diagnosis. [reviewSignals] owns
/// the user-facing finding count and ordering, including non-interaction
/// findings such as nutrient upper-limit signals.
@immutable
class StackHealthSnapshot {
  final StackIntelligence intelligence;
  final List<ClinicalSignal> reviewSignals;
  final bool checksIncomplete;
  final bool coverageIncomplete;

  const StackHealthSnapshot({
    required this.intelligence,
    required this.reviewSignals,
    required this.checksIncomplete,
    required this.coverageIncomplete,
  });
}

@immutable
class StackIntelligenceEngine {
  const StackIntelligenceEngine();

  /// Builds the single presentation-neutral Stack Health snapshot used by
  /// Home and the Stack tab. Callers format the same count with the shared
  /// consumer copy helper; they do not reconstruct interaction-only totals.
  StackHealthSnapshot summarizeFromReports({
    required int stackSize,
    required StackSafetyReport safetyReport,
    required RecalledIngredientsReport recalledReport,
    required SynergyReport synergyReport,
    List<StackDoseThresholdAlert> doseThresholdAlerts = const [],
  }) {
    return StackHealthSnapshot(
      intelligence: diagnoseFromReports(
        stackSize: stackSize,
        safetyReport: safetyReport,
        recalledReport: recalledReport,
        synergyReport: synergyReport,
        doseThresholdAlerts: doseThresholdAlerts,
      ),
      reviewSignals: List<ClinicalSignal>.unmodifiable(
        orderedSignalsFrom(
          safetyReport,
          doseThresholdAlerts: doseThresholdAlerts,
        ),
      ),
      checksIncomplete: safetyReport.checksIncomplete,
      coverageIncomplete: safetyReport.coverageIncomplete,
    );
  }

  /// Compose the full stack-health verdict from the shared report types.
  ///
  /// This is the preferred entry point for UI surfaces. It keeps the
  /// interaction issue flattening and synergy-to-quality-score mapping in one
  /// service-layer place so Home, Stack, and clinician share views do not drift.
  StackIntelligence diagnoseFromReports({
    required int stackSize,
    required StackSafetyReport safetyReport,
    required RecalledIngredientsReport recalledReport,
    required SynergyReport synergyReport,
    List<StackDoseThresholdAlert> doseThresholdAlerts = const [],
  }) {
    final safetyScore = const StackSafetyScorer().compute(
      issues: _interactionIssuesForScore(safetyReport),
      synergies: _synergyResultsForScore(synergyReport),
    );

    return diagnose(
      stackSize: stackSize,
      safetyReport: safetyReport,
      recalledReport: recalledReport,
      synergyReport: synergyReport,
      qualityScore: safetyScore.score,
      doseThresholdAlerts: doseThresholdAlerts,
    );
  }

  /// Compose existing reports into a single [StackIntelligence] verdict.
  ///
  /// [qualityScore] is the optional 0..100 internal stack score
  /// (typically `StackSafetyScorer.compute(...).score`). When omitted, a
  /// clean stack cannot promote past `decent`.
  ///
  /// [synergyReport] is currently unused for the tier verdict — synergy
  /// is positive guidance, not a safety signal. It is accepted so the
  /// caller wiring matches the spec and so future revisions can lift
  /// strong-synergy bonuses into the score without changing the
  /// signature.
  StackIntelligence diagnose({
    required int stackSize,
    required StackSafetyReport safetyReport,
    required RecalledIngredientsReport recalledReport,
    required SynergyReport synergyReport,
    int? qualityScore,
    List<StackDoseThresholdAlert> doseThresholdAlerts = const [],
  }) {
    final hasBannedIngredient = recalledReport.violations.any(
      (violation) => violation.isBannedSubstance,
    );
    final hasRecalledIngredient = !recalledReport.isEmpty;
    final analysisIncomplete =
        safetyReport.checksIncomplete ||
        safetyReport.coverageIncomplete ||
        recalledReport.incomplete ||
        doseThresholdAlerts.any((alert) => alert.isIncomplete);

    final allInteractions = <InteractionResult>[
      ...safetyReport.medicationPairInteractions,
      ...safetyReport.medicationInteractions,
      ...safetyReport.stackInteractions,
      ...safetyReport.categoryWarnings,
    ];

    int countBy(Severity s) =>
        allInteractions.where((i) => i.severity == s).length +
        safetyReport.medicationProfileWarnings
            .where((warning) => warning.severity == s)
            .length;

    final contraindicatedCount = countBy(Severity.contraindicated);
    final avoidCount = countBy(Severity.avoid);
    final cautionCount = countBy(Severity.caution);
    final monitorCount = countBy(Severity.monitor);
    final hasContraindicatedInteraction = contraindicatedCount > 0;
    final interactionCount =
        contraindicatedCount + avoidCount + cautionCount + monitorCount;

    final nutrientWarningCount =
        safetyReport.nutrientStatuses.where((n) => n.shouldWarn).length +
        doseThresholdAlerts.length;

    final tier = StackIntelligence.deriveTier(
      stackSize: stackSize,
      hasBannedIngredient: hasBannedIngredient,
      hasRecalledIngredient: hasRecalledIngredient,
      hasContraindicatedInteraction: hasContraindicatedInteraction,
      avoidInteractionCount: avoidCount,
      cautionInteractionCount: cautionCount,
      monitorInteractionCount: monitorCount,
      nutrientWarningCount: nutrientWarningCount,
      qualityScore: qualityScore,
      missingData: analysisIncomplete,
    );

    final issues = _composeIssues(
      safetyReport: safetyReport,
      recalledReport: recalledReport,
      doseThresholdAlerts: doseThresholdAlerts,
    );

    return StackIntelligence(
      tier: tier,
      stackSize: stackSize,
      issues: issues,
      interactionCount: interactionCount,
      nutrientWarningCount: nutrientWarningCount,
      hasRecalledIngredient: hasRecalledIngredient,
      hasContraindicatedInteraction: hasContraindicatedInteraction,
      hasBannedIngredient: hasBannedIngredient,
      analysisIncomplete: analysisIncomplete,
      qualityScore: qualityScore,
    );
  }

  List<StackIssue> _composeIssues({
    required StackSafetyReport safetyReport,
    required RecalledIngredientsReport recalledReport,
    required List<StackDoseThresholdAlert> doseThresholdAlerts,
  }) {
    final out = <StackIssue>[];

    for (final v in recalledReport.orderedViolations) {
      out.add(StackIssue(severity: v.worstSeverity, headline: v.bannerMessage));
    }

    // Organized by the typed signal collection: disposition-first (block/review
    // actionable summaries lead, good_to_know context follows) with suppress
    // excluded upstream. The engine READS the envelope's ordering and each
    // payload's authored severity/copy — it never re-derives severity,
    // disposition, or medical conclusions.
    for (final signal in orderedSignalsFrom(
      safetyReport,
      doseThresholdAlerts: doseThresholdAlerts,
    )) {
      switch (signal.payload) {
        case InteractionPayload(:final result):
          out.add(
            StackIssue(severity: result.severity, headline: result.mechanism),
          );
        case MedicationProfilePayload(:final warning):
          out.add(
            StackIssue(
              severity: warning.severity,
              headline: _medicationProfileIssueHeadline(warning),
            ),
          );
        case CumulativeExposurePayload(:final status):
          final warning = status.warning;
          if (warning == null && status.tier != NutrientTier.exceedsUl) {
            continue;
          }
          final hasUpperLimitDetail =
              status.ul != null && status.pctOfUl != null;
          out.add(
            StackIssue(
              severity: StackSafetyReport.severityForNutrient(status),
              headline:
                  status.tier == NutrientTier.exceedsUl && hasUpperLimitDetail
                  ? StackSafetyReport.nutrientUpperLimitSummary(status)
                  : warning!,
            ),
          );
        case DoseThresholdPayload():
          out.add(
            StackIssue(
              severity: signal.clinicalSeverity,
              headline: signal.body,
            ),
          );
        case MedicationNutrientPayload():
          // Depletions are not part of the safety report's aggregation.
          continue;
        case TimingSeparationPayload():
          // Timing separations are not wired into the aggregator until the unified Clinical Guidance work lands, so this cannot arrive yet. The adapter exists now on purpose: it is the shape the rule audit is written against. Asserted unreachable by clinical_signal_timing_adapter_test.dart.
          continue;
      }
    }

    return out;
  }

  String _medicationProfileIssueHeadline(MedicationProfileWarning warning) {
    return '${warning.medicationName}: ${warning.headline}';
  }

  List<InteractionResult> _interactionIssuesForScore(
    StackSafetyReport safetyReport,
  ) {
    return <InteractionResult>[
      ...safetyReport.medicationPairInteractions,
      ...safetyReport.medicationInteractions,
      ...safetyReport.stackInteractions,
      ...safetyReport.categoryWarnings,
    ];
  }

  List<core_models.SynergyResult> _synergyResultsForScore(
    SynergyReport synergyReport,
  ) {
    return synergyReport.matches
        .map(
          (match) => core_models.SynergyResult(
            ingredient1: match.matchedIngredients.isNotEmpty
                ? match.matchedIngredients.first
                : match.clusterId,
            ingredient2: match.matchedIngredients.length > 1
                ? match.matchedIngredients[1]
                : match.clusterName,
            description: match.mechanism,
            evidenceLevel: EvidenceLevel.established,
            bonus: match.bonusPoints,
          ),
        )
        .toList(growable: false);
  }
}
