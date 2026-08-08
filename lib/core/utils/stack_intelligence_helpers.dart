import 'package:pharmaguide/core/models/stack_intelligence.dart';

/// Shared consumer noun and count for the Stack safety summary, warning card,
/// and detail sheet. Every caller supplies the length of the same typed signal
/// collection so nutrient-limit findings are never omitted as "not an
/// interaction".
String describeSafetySignalReview(int count) {
  if (count <= 0) return 'No safety signals to review';
  return '$count safety ${count == 1 ? 'signal' : 'signals'} to review';
}

/// Shared one-line insight describing the user's stack health.
///
/// Identical copy across surfaces — the Home Stack-Health card and
/// the Stack-tab summary card both render the same diagnostic string
/// so the user never sees two different verdicts at once. Verbatim
/// port of the production `_StackSummaryCard._describeSummary`.
String describeStackSummary(StackIntelligence? intelligence) {
  if (intelligence == null) {
    return 'Reviewing interactions, recall alerts, and nutrient overlap.';
  }
  final incompleteSuffix = intelligence.analysisIncomplete
      ? ' Some checks are unavailable.'
      : '';
  switch (intelligence.tier) {
    case StackTier.unsafe:
      if (intelligence.hasBannedIngredient) {
        return 'Banned ingredient found — review immediately.';
      }
      if (intelligence.hasRecalledIngredient) {
        return 'Recalled ingredient found — review immediately.';
      }
      if (intelligence.hasContraindicatedInteraction) {
        return 'Contraindicated interaction found — review immediately.';
      }
      return 'High-risk issue found — review immediately.';
    case StackTier.concerning:
      if (intelligence.interactionCount > 0 &&
          intelligence.nutrientWarningCount > 0) {
        return '${intelligence.interactionCount} interaction'
            '${intelligence.interactionCount == 1 ? '' : 's'} and '
            '${intelligence.nutrientWarningCount} nutrient warning'
            '${intelligence.nutrientWarningCount == 1 ? '' : 's'} need review.'
            '$incompleteSuffix';
      }
      if (intelligence.interactionCount > 0) {
        return '${intelligence.interactionCount} interaction'
            '${intelligence.interactionCount == 1 ? '' : 's'} need review.'
            '$incompleteSuffix';
      }
      if (intelligence.nutrientWarningCount > 0) {
        return '${intelligence.nutrientWarningCount} nutrient warning'
            '${intelligence.nutrientWarningCount == 1 ? '' : 's'} need review.'
            '$incompleteSuffix';
      }
      return 'Important issues found — review this stack.$incompleteSuffix';
    case StackTier.decent:
      if (intelligence.interactionCount > 0) {
        return '${intelligence.interactionCount} interaction'
            '${intelligence.interactionCount == 1 ? '' : 's'} worth reviewing.'
            '$incompleteSuffix';
      }
      if (intelligence.nutrientWarningCount > 0) {
        return '${intelligence.nutrientWarningCount} nutrient warning'
            '${intelligence.nutrientWarningCount == 1 ? '' : 's'} worth reviewing.'
            '$incompleteSuffix';
      }
      if (intelligence.analysisIncomplete) {
        return 'Some safety checks could not be completed. This is not an '
            'all-clear.';
      }
      return 'Some concerns are worth reviewing.';
    // Solid and Optimized are only reachable when the analysis completed
    // (missingData routes to `incomplete` first), so scoping the claim to
    // "the checks PharmaGuide completed" is always truthful here.
    case StackTier.solid:
      return 'No major safety issues found. Minor items may be worth '
          'monitoring.';
    case StackTier.optimized:
      return 'No significant issues found in the checks PharmaGuide '
          'completed.';
    case StackTier.incomplete:
      return 'Some checks need more information before this stack can be rated.';
  }
}
