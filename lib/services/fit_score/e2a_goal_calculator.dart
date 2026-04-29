import 'package:pharmaguide/core/extensions/json_helpers.dart';

/// E2a Goal Alignment Calculator (legacy/fallback path).
///
/// Used ONLY when `products_core.goal_matches` hasn't been populated by the
/// pipeline yet. The authoritative goal-matching contract lives in
/// `scripts/build_final_db.py::compute_goal_matches` (schema v6.0.0).
///
/// Algorithm must stay in lockstep with the pipeline so results are
/// consistent when a product transitions from "fallback-only" to
/// "pipeline-populated":
///   * Skip goal if ANY `blocked_by_clusters` is present.
///   * Skip goal if `required_clusters` is non-empty and none are present.
///   * score = matched_weight / max_weight (normalized 0.0..1.0).
///   * Include goal iff score >= min_match_score.
///
/// Final 0..2 score is the pipeline confidence (average of matched goal
/// scores) scaled by the ratio of matched-vs-requested user goals.
class E2aGoalCalculator {
  final Map<String, dynamic> goalData;

  E2aGoalCalculator(this.goalData);

  double calculate({
    required List<String> productClusters,
    required List<String> userGoals,
  }) {
    if (userGoals.isEmpty || productClusters.isEmpty) return 0.0;

    final mappings = goalData.safeList('user_goal_mappings');
    final clusterSet = productClusters.toSet();
    double confidenceSum = 0.0;
    int matchedGoals = 0;

    for (final goalId in userGoals) {
      final goalMapping = mappings.cast<Map<String, dynamic>?>().firstWhere(
        (m) => m != null && m['id'] == goalId,
        orElse: () => null,
      );
      if (goalMapping == null) continue;

      final rawWeights = goalMapping['cluster_weights'];
      final Map<String, num> clusterWeights = {};
      if (rawWeights is Map) {
        for (final entry in rawWeights.entries) {
          final value = entry.value;
          if (value is num) clusterWeights[entry.key.toString()] = value;
        }
      }
      final requiredClusters = goalMapping.safeStringList('required_clusters');
      final blockedClusters = goalMapping.safeStringList('blocked_by_clusters');
      final minMatchScore = goalMapping.safeDouble('min_match_score', 0.5);

      // Gate 1: blocked clusters disqualify regardless of score.
      if (blockedClusters.any(clusterSet.contains)) continue;

      // Gate 2: required clusters must have at least one present.
      if (requiredClusters.isNotEmpty &&
          !requiredClusters.any(clusterSet.contains)) {
        continue;
      }

      // Gate 3: normalized weighted score must meet threshold.
      double maxWeight = 0.0;
      for (final w in clusterWeights.values) {
        maxWeight += w.toDouble();
      }
      if (maxWeight <= 0.0) continue;

      double matchedWeight = 0.0;
      for (final cluster in clusterSet) {
        final w = clusterWeights[cluster];
        if (w != null) matchedWeight += w.toDouble();
      }
      final score = matchedWeight / maxWeight;

      if (score >= minMatchScore) {
        confidenceSum += score;
        matchedGoals++;
      }
    }

    if (matchedGoals == 0) return 0.0;

    // Output in the legacy 0.0..2.0 range expected by FitScoreService.
    // Mirrors fit_score_service._goalAlignmentScore:
    //   2.0 * (matched/requested) * avg_confidence
    final avgConfidence = (confidenceSum / matchedGoals).clamp(0.0, 1.0);
    final matchedRatio = matchedGoals / userGoals.length;
    return (2.0 * matchedRatio * avgConfidence).clamp(0.0, 2.0);
  }
}
