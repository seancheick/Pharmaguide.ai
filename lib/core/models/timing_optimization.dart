import 'package:pharmaguide/core/constants/severity.dart';

/// The type of timing advice a rule provides.
enum TimingRuleType {
  /// Two ingredients should be taken at different times.
  separate,

  /// Two ingredients are best taken together for synergy.
  takeTogether,

  /// An ingredient should be taken with food/fat for absorption.
  takeWithFood,

  /// An ingredient is best taken on an empty stomach.
  takeOnEmptyStomach,

  /// An ingredient is best at a specific time of day.
  timeOfDay;

  static TimingRuleType fromString(String value) {
    switch (value.toLowerCase().replaceAll(' ', '_')) {
      case 'separate':
        return TimingRuleType.separate;
      case 'take_together':
        return TimingRuleType.takeTogether;
      case 'take_with_food':
        return TimingRuleType.takeWithFood;
      case 'take_on_empty_stomach':
        return TimingRuleType.takeOnEmptyStomach;
      case 'time_of_day':
        return TimingRuleType.timeOfDay;
      default:
        return TimingRuleType.separate;
    }
  }
}

/// A single timing optimization recommendation for the user's stack.
///
/// Produced by [TimingEvaluationService] when two items in the user's stack
/// match a timing rule. The UI renders these as actionable cards in the
/// stack safety report.
class TimingOptimization {
  /// The rule ID from timing_rules.json (e.g., "timing_iron_calcium_separate").
  final String ruleId;

  /// Display name of the first ingredient/medication involved.
  final String ingredient1;

  /// Display name of the second ingredient/medication involved.
  final String ingredient2;

  /// User-facing advice text (≤300 chars, consumer-friendly).
  final String advice;

  /// The type of timing recommendation.
  final TimingRuleType ruleType;

  /// How many hours to separate (null for non-separation rules).
  final int? separationHours;

  /// Impact on the stack safety score (negative = penalty for not following).
  final int scoreImpact;

  /// Evidence backing this recommendation.
  final EvidenceLevel evidenceLevel;

  /// Brief mechanism explanation (for "Learn more" expansion).
  final String? mechanism;

  /// Source URLs for the user to verify.
  final List<String> sourceUrls;

  /// Name of the product in the user's stack that triggered ingredient1.
  final String? product1Name;

  /// Name of the product in the user's stack that triggered ingredient2.
  final String? product2Name;

  const TimingOptimization({
    required this.ruleId,
    required this.ingredient1,
    required this.ingredient2,
    required this.advice,
    required this.ruleType,
    this.separationHours,
    required this.scoreImpact,
    required this.evidenceLevel,
    this.mechanism,
    this.sourceUrls = const [],
    this.product1Name,
    this.product2Name,
  });

  /// Whether this is a separation rule (the most actionable type).
  bool get isSeparation => ruleType == TimingRuleType.separate;

  /// Medication names that appear in timing rules. Mirrors
  /// `TimingEvaluationService._medicationKeywords` — the rule can carry
  /// the medication on either side, so both ingredients are checked.
  static const _medicationNames = ['levothyroxine', 'warfarin'];

  /// Whether this involves a medication (higher urgency).
  ///
  /// Checks both ingredient display names, case-insensitively —
  /// [TimingRuleType] does not encode medication involvement, so the
  /// ingredient names are the only signal available on the model.
  bool get involvesMedication {
    final i1 = ingredient1.toLowerCase();
    final i2 = ingredient2.toLowerCase();
    return _medicationNames.any((m) => i1.contains(m) || i2.contains(m));
  }

  /// Clinical importance tier (higher = more important), mirroring the
  /// research prioritization in `knowledge/timing-rules-research.md`:
  ///   3 — a medication can lose efficacy (drug–nutrient): always surface
  ///   2 — supplement absorption that can genuinely matter (separations)
  ///   1 — optimization niceties (with food, synergy, time of day)
  ///
  /// Cumulative-dose safety (e.g. zinc→copper) and folklore (Ca↔Mg, evening
  /// magnesium) are deliberately NOT timing tiers — they were removed from
  /// the ruleset; dose-safety belongs in the UL/nutrient checks.
  int get tier {
    if (involvesMedication) return 3;
    if (isSeparation) return 2;
    return 1;
  }

  /// Display ordering: tier dominates; evidence strength breaks ties so a
  /// well-evidenced tip outranks a theoretical one within the same tier.
  int get displayPriority {
    final evidenceBump = switch (evidenceLevel) {
      EvidenceLevel.established => 2,
      EvidenceLevel.probable => 1,
      EvidenceLevel.theoretical => 0,
      EvidenceLevel.ungraded => -1,
    };
    return tier * 10 + evidenceBump;
  }
}
