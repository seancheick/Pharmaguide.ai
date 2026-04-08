/// E2a Goal Alignment Calculator.
/// Matches product synergy clusters against user's selected goals.
class E2aGoalCalculator {
  final Map<String, dynamic> goalData;

  E2aGoalCalculator(this.goalData);

  double calculate({
    required List<String> productClusters,
    required List<String> userGoals,
  }) {
    if (userGoals.isEmpty || productClusters.isEmpty) return 0.0;

    final mappings = goalData['user_goal_mappings'] as List? ?? [];
    double totalWeight = 0.0;
    int matchedGoals = 0;

    for (final goalId in userGoals) {
      final goalMapping = mappings.cast<Map<String, dynamic>?>().firstWhere(
            (m) => m != null && m['id'] == goalId,
            orElse: () => null,
          );
      if (goalMapping == null) continue;

      final clusterWeights =
          (goalMapping['cluster_weights'] as Map?)?.cast<String, num>() ?? {};
      final antiClusters =
          (goalMapping['anti_clusters'] as List?)?.cast<String>() ?? [];

      double goalScore = 0.0;
      for (final cluster in productClusters) {
        if (antiClusters.contains(cluster)) continue; // Anti-clusters score 0
        final weight = clusterWeights[cluster];
        if (weight != null) {
          goalScore += weight.toDouble();
        }
      }

      if (goalScore > 0) {
        totalWeight += goalScore.clamp(0.0, 1.0); // Cap per goal
        matchedGoals++;
      }
    }

    // Normalize to 0-2 scale
    if (matchedGoals == 0) return 0.0;
    return (totalWeight / userGoals.length * 2.0).clamp(0.0, 2.0);
  }
}
