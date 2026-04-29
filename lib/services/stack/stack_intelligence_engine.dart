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
import 'package:pharmaguide/core/models/stack_intelligence.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

@immutable
class StackIntelligenceEngine {
  const StackIntelligenceEngine();

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
        allInteractions.where((i) => i.severity == s).length;

    final contraindicatedCount = countBy(Severity.contraindicated);
    final avoidCount = countBy(Severity.avoid);
    final cautionCount = countBy(Severity.caution);
    final monitorCount = countBy(Severity.monitor);
    final hasContraindicatedInteraction = contraindicatedCount > 0;
    final interactionCount =
        contraindicatedCount + avoidCount + cautionCount + monitorCount;

    final nutrientWarningCount = safetyReport.nutrientStatuses
        .where((n) => n.shouldWarn)
        .length;

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

    return out;
  }
}
