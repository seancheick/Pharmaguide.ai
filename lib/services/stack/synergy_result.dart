import 'package:pharmaguide/core/constants/severity.dart';

/// Single synergy match: a cluster that has been detected in the user's stack.
class SynergyMatch {
  final String clusterId;
  final String clusterName;
  final List<String> matchedIngredients;
  final String mechanism;
  final int bonusPoints;
  final String evidenceTier; // 'strong', 'moderate', 'limited'
  final List<String> citations;

  SynergyMatch({
    required this.clusterId,
    required this.clusterName,
    required this.matchedIngredients,
    required this.mechanism,
    required this.bonusPoints,
    required this.evidenceTier,
    required this.citations,
  });

  /// Human-readable evidence label for display
  String get evidenceLabel {
    switch (evidenceTier) {
      case 'strong':
        return 'Strong evidence';
      case 'moderate':
        return 'Moderate evidence';
      case 'limited':
        return 'Limited evidence';
      default:
        return 'Evidence pending';
    }
  }

  /// Severity based on evidence tier (for display priority)
  Severity get displaySeverity {
    switch (evidenceTier) {
      case 'strong':
        return Severity.safe; // Green badge
      case 'moderate':
        return Severity.monitor; // Blue badge
      default:
        return Severity.safe;
    }
  }
}

/// Aggregated synergy result for a user's stack.
class SynergyReport {
  final List<SynergyMatch> matches;
  final int totalBonusPoints;

  bool get isEmpty => matches.isEmpty;

  SynergyReport({required this.matches, required this.totalBonusPoints});

  factory SynergyReport.empty() {
    return SynergyReport(matches: const [], totalBonusPoints: 0);
  }

  /// Synergies sorted by evidence tier (strong first) then bonus points (high first)
  List<SynergyMatch> get orderedMatches {
    final sorted = [...matches];
    sorted.sort((a, b) {
      // Strong evidence first
      final tierOrder = {'strong': 0, 'moderate': 1, 'limited': 2};
      final aTier = tierOrder[a.evidenceTier] ?? 99;
      final bTier = tierOrder[b.evidenceTier] ?? 99;
      if (aTier != bTier) return aTier.compareTo(bTier);
      // Then by bonus points descending
      return b.bonusPoints.compareTo(a.bonusPoints);
    });
    return sorted;
  }
}
