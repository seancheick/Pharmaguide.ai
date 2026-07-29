import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/stack_safety_score.dart';

/// Diagnostic tier verdict for a user's stack.
///
/// Locked vocabulary (see `INITIATIVE_STACK_INTELLIGENCE.md`). The five
/// user-facing tiers map 1:1 to [StackHealthLabel]; `incomplete` is an
/// internal fallback rendered as neutral "more info needed" copy, never
/// as a graded label.
enum StackTier {
  optimized,
  solid,
  decent,
  concerning,
  unsafe,
  incomplete;

  /// Matching [StackHealthLabel] for the five user-facing tiers, or
  /// `null` when this is the internal `incomplete` fallback.
  StackHealthLabel? get healthLabel => switch (this) {
    StackTier.optimized => StackHealthLabel.optimized,
    StackTier.solid => StackHealthLabel.solid,
    StackTier.decent => StackHealthLabel.decent,
    StackTier.concerning => StackHealthLabel.concerning,
    StackTier.unsafe => StackHealthLabel.unsafe,
    StackTier.incomplete => null,
  };
}

/// One actionable issue surfaced in the diagnosis. [severity] reuses the
/// project-wide [Severity] enum so callers can sort/group alongside
/// existing reports.
class StackIssue {
  final Severity severity;
  final String headline;

  const StackIssue({required this.severity, required this.headline});
}

/// Diagnostic output of `StackIntelligenceEngine` (B2). The model itself
/// is intentionally lean: tier derivation lives here, composition of the
/// underlying reports belongs in the engine.
class StackIntelligence {
  final StackTier tier;
  final int stackSize;
  final List<StackIssue> issues;
  final int interactionCount;
  final int nutrientWarningCount;
  final bool hasRecalledIngredient;
  final bool hasContraindicatedInteraction;
  final bool hasBannedIngredient;
  final bool analysisIncomplete;

  /// 0..100 internal stack quality score. Secondary signal only — never
  /// surfaced as a headline. `null` when the stack is too thin to score.
  final int? qualityScore;

  const StackIntelligence({
    required this.tier,
    required this.stackSize,
    required this.issues,
    required this.interactionCount,
    required this.nutrientWarningCount,
    required this.hasRecalledIngredient,
    required this.hasContraindicatedInteraction,
    required this.hasBannedIngredient,
    this.analysisIncomplete = false,
    this.qualityScore,
  });

  /// Pure-function tier derivation. Hard safety gates always win; the
  /// `qualityScore` only differentiates clean stacks at the top.
  ///
  /// Rules, top-down:
  ///   - empty stack                                                 → incomplete
  ///   - banned / recalled / contraindicated                         → unsafe
  ///   - avoid-level interaction OR ≥2 nutrient warnings             → concerning
  ///   - caution-level OR exactly 1 nutrient warning                 → decent
  ///   - `missingData` flag on an otherwise-clean stack              → decent
  ///   - clean stack, no quality score                               → decent
  ///   - monitor-only clean stack caps `optimized` at `solid`
  ///   - clean stack, qualityScore ≥ 85                              → optimized
  ///   - clean stack, qualityScore ≥ 70                              → solid
  ///   - clean stack, qualityScore < 70                              → decent
  static StackTier deriveTier({
    required int stackSize,
    required bool hasBannedIngredient,
    required bool hasRecalledIngredient,
    required bool hasContraindicatedInteraction,
    required int avoidInteractionCount,
    required int cautionInteractionCount,
    required int monitorInteractionCount,
    required int nutrientWarningCount,
    int? qualityScore,
    bool missingData = false,
  }) {
    if (stackSize == 0) return StackTier.incomplete;

    if (hasBannedIngredient ||
        hasRecalledIngredient ||
        hasContraindicatedInteraction) {
      return StackTier.unsafe;
    }

    if (avoidInteractionCount > 0 || nutrientWarningCount >= 2) {
      return StackTier.concerning;
    }

    if (cautionInteractionCount > 0 || nutrientWarningCount == 1) {
      return StackTier.decent;
    }

    if (missingData || qualityScore == null) return StackTier.decent;
    if (qualityScore >= 85) {
      return monitorInteractionCount > 0
          ? StackTier.solid
          : StackTier.optimized;
    }
    if (qualityScore >= 70) return StackTier.solid;
    return StackTier.decent;
  }
}
