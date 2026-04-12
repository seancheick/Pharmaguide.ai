import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/stack_safety_score.dart';
import 'package:pharmaguide/core/models/synergy_result.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';

/// Computes the Stack Safety Score (0-100).
///
/// Formula:
///   score = 100 - interaction_penalties + synergy_bonuses
///   Hard-stop: contraindicated caps at 25, avoid caps at 50
///   Floor: 25 (max deduction 75), Ceiling: 100 (max bonus 15)
class StackSafetyScorer {
  const StackSafetyScorer();

  StackSafetyScore compute({
    required List<InteractionResult> issues,
    List<SynergyResult> synergies = const [],
    List<TimingOptimization> optimizations = const [],
  }) {
    // Calculate penalties
    int totalPenalty = 0;
    bool hasContraindicated = false;
    bool hasAvoid = false;

    for (final issue in issues) {
      totalPenalty += InteractionResult.stackPenaltyFor(issue.severity).abs();
      if (issue.severity == Severity.contraindicated) {
        hasContraindicated = true;
      }
      if (issue.severity == Severity.avoid) hasAvoid = true;
    }

    // Calculate bonuses
    int totalBonus = 0;
    for (final synergy in synergies) {
      totalBonus += synergy.bonus;
    }
    totalBonus = totalBonus.clamp(0, 15); // Max bonus 15

    // Compute score
    int score = 100 - totalPenalty + totalBonus;

    // Hard-stop caps
    if (hasContraindicated) {
      score = score.clamp(0, 25);
    } else if (hasAvoid) {
      score = score.clamp(0, 50);
    }

    // Floor and ceiling
    score = score.clamp(25, 100);

    // Empty stack = perfect score
    if (issues.isEmpty && synergies.isEmpty) score = 100;

    final riskTier = RiskTier.fromScore(score);

    return StackSafetyScore(
      score: score,
      riskTier: riskTier,
      issues: issues,
      synergies: synergies,
      optimizations: optimizations,
    );
  }
}
