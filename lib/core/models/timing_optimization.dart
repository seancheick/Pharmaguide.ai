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
        throw FormatException('Unknown timing rule type: $value');
    }
  }
}

/// Pipeline-authored scheduling buckets for a time-of-day rule.
///
/// These are coarse routine anchors, not invented clock-time prescriptions.
/// A `time_of_day` rule must name one or more of these in structured data;
/// consumer prose is never parsed to decide where a product belongs.
enum DailySlot {
  morningEmpty('morning_empty', 'Morning, before food', 7),
  withBreakfast('with_breakfast', 'With breakfast', 8),
  withDinner('with_dinner', 'With dinner', 18),
  bedtime('bedtime', 'Before bed', 22);

  const DailySlot(this.wireValue, this.label, this.anchorHour);

  final String wireValue;
  final String label;
  final int anchorHour;

  bool get isWithFood => this == withBreakfast || this == withDinner;

  static DailySlot fromString(String value) {
    final normalized = value.trim().toLowerCase();
    return DailySlot.values.firstWhere(
      (slot) => slot.wireValue == normalized,
      orElse: () => throw FormatException('Unknown daily slot: $value'),
    );
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

  /// Stable local stack-row identity for [product1Name].
  ///
  /// Display names are not identifiers: two bottles may share a name, and
  /// fuzzy name matching can attach a plan slot to the wrong row.
  final String? product1StackEntryId;

  /// Name of the product in the user's stack that triggered ingredient2.
  final String? product2Name;

  /// Stable local stack-row identity for [product2Name].
  final String? product2StackEntryId;

  /// Whether a reviewed RxCUI on the timing rule matched a saved medication.
  final bool involvesMedication;

  /// Structured scheduling choices authored on a `time_of_day` rule.
  ///
  /// Empty for every other rule type. The sequence resolver fails closed when
  /// a time-of-day optimization reaches it without this structure.
  final Set<DailySlot> allowedDailySlots;

  /// Whether the pipeline permits this rule to drive the resolved daily plan.
  ///
  /// Some accurate informational rules depend on a purpose, formulation, or
  /// unspecified medication schedule the app does not capture. They remain
  /// visible as authored advice but must not be turned into a concrete slot.
  final bool dailyPlanEligible;

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
    this.product1StackEntryId,
    this.product2Name,
    this.product2StackEntryId,
    this.involvesMedication = false,
    this.allowedDailySlots = const {},
    this.dailyPlanEligible = true,
  });

  /// Whether this is a separation rule (the most actionable type).
  bool get isSeparation => ruleType == TimingRuleType.separate;

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
      EvidenceLevel.moderate => 1,
      EvidenceLevel.limited => 0,
      EvidenceLevel.theoretical => 0,
      EvidenceLevel.noData => -1,
      EvidenceLevel.ungraded => -1,
    };
    return tier * 10 + evidenceBump;
  }
}
