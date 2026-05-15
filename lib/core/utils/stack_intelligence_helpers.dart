import 'package:pharmaguide/core/models/stack_intelligence.dart';

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
            '${intelligence.nutrientWarningCount == 1 ? '' : 's'} need review.';
      }
      if (intelligence.interactionCount > 0) {
        return '${intelligence.interactionCount} interaction'
            '${intelligence.interactionCount == 1 ? '' : 's'} need review.';
      }
      if (intelligence.nutrientWarningCount > 0) {
        return '${intelligence.nutrientWarningCount} nutrient warning'
            '${intelligence.nutrientWarningCount == 1 ? '' : 's'} need review.';
      }
      return 'Important issues found — review this stack.';
    case StackTier.decent:
      if (intelligence.interactionCount > 0) {
        return '${intelligence.interactionCount} interaction'
            '${intelligence.interactionCount == 1 ? '' : 's'} worth reviewing.';
      }
      if (intelligence.nutrientWarningCount > 0) {
        return '${intelligence.nutrientWarningCount} nutrient warning'
            '${intelligence.nutrientWarningCount == 1 ? '' : 's'} worth reviewing.';
      }
      return 'Some concerns are worth reviewing.';
    case StackTier.solid:
    case StackTier.optimized:
      return 'No major safety issues detected right now.';
    case StackTier.incomplete:
      return 'Add more information to diagnose this stack.';
  }
}
