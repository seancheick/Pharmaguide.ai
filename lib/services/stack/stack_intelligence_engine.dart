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
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/stack_safety_scorer.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

@immutable
class StackIntelligenceEngine {
  const StackIntelligenceEngine();

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
      (v) => v.recalledIngredients.any((r) => r.recallStatus == 'banned'),
    );
    final hasRecalledIngredient = !recalledReport.isEmpty;

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

    for (final entry in safetyReport.orderedWarnings) {
      if (entry is InteractionResult) {
        out.add(
          StackIssue(severity: entry.severity, headline: entry.mechanism),
        );
      } else if (entry is MedicationProfileWarning) {
        out.add(
          StackIssue(
            severity: entry.severity,
            headline: _medicationProfileIssueHeadline(entry),
          ),
        );
      } else if (entry is NutrientStatus) {
        final warning = entry.warning;
        if (warning == null) continue;
        out.add(
          StackIssue(
            severity: entry.tier == NutrientTier.exceedsUl
                ? Severity.avoid
                : Severity.caution,
            headline: warning,
          ),
        );
      }
    }

    for (final alert in doseThresholdAlerts) {
      out.add(
        StackIssue(
          severity: Severity.caution,
          headline: alert.isIncomplete
              ? 'Cumulative ${alert.displayName} could not be fully evaluated; '
                    'known subtotal is ${_formatDose(alert.totalValue)} '
                    '${alert.unit} across your stack (threshold '
                    '${_formatDose(alert.thresholdValue)} '
                    '${alert.thresholdUnit}).'
              : 'Cumulative ${alert.displayName} is '
                    '${_formatDose(alert.totalValue)} ${alert.unit} across '
                    'your stack (threshold '
                    '${_formatDose(alert.thresholdValue)} '
                    '${alert.thresholdUnit}).',
        ),
      );
    }

    return out;
  }

  String _formatDose(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
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
