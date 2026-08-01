import 'package:pharmaguide/core/constants/severity.dart';

/// The shape of a timing relation.
///
/// This replaces the old `rule_type`. The critical difference: a relation is
/// always expressed against something the user already controls — a meal, an
/// empty stomach, another bottle, an event they define — and never against a
/// clock time the app invented. There is no `time_of_day`, because the app does
/// not know when the user wakes, eats, fasts, or sleeps.
///
/// `separateFrom` is the only binary relation. Every other type constrains one
/// product on its own.
enum TimingRelationType {
  separateFrom('separate_from'),

  /// Separate from *any* medication, with no specific second identity — the
  /// shape of a bulk binder like psyllium. Unary on purpose: inventing a
  /// concrete second bottle here would be a fake identity.
  separateFromMedications('separate_from_medications'),

  withFood('with_food'),
  emptyStomach('empty_stomach'),
  beforeEvent('before_event'),
  afterEvent('after_event'),
  consistentRelativeToPrescription('consistent_relative_to_prescription');

  const TimingRelationType(this.wireValue);

  final String wireValue;

  /// True when the relation names a second physical stack item.
  bool get isBinary => this == separateFrom;

  static TimingRelationType fromString(String value) {
    final normalized = value.trim().toLowerCase();
    return TimingRelationType.values.firstWhere(
      (type) => type.wireValue == normalized,
      orElse: () => throw FormatException('Unknown timing relation: $value'),
    );
  }
}

/// An anchor the *user* defines, never one the app assigns.
///
/// "30–60 minutes before intended sleep" is defensible because the user knows
/// when they intend to sleep. "Before bed = 10 PM" is invented. Only events the
/// user can answer for themselves belong here.
enum TimingEvent {
  intendedSleep('intended_sleep'),

  /// A meal, as the user takes it. Anchors "30 minutes before a meal" without
  /// the app deciding when meals happen.
  meal('meal');

  const TimingEvent(this.wireValue);

  final String wireValue;

  static TimingEvent fromString(String value) {
    final normalized = value.trim().toLowerCase();
    return TimingEvent.values.firstWhere(
      (event) => event.wireValue == normalized,
      orElse: () => throw FormatException('Unknown timing event: $value'),
    );
  }
}

/// A structured, pipeline-authored timing relation.
///
/// Structured rather than prose so it stays machine-testable: a test can assert
/// that no relation is ever rendered as a clock time, which prose alone cannot
/// guarantee.
class TimingRelation {
  const TimingRelation({
    required this.type,
    this.minimumHours,
    this.event,
    this.minimumMinutes,
    this.maximumMinutes,
  });

  final TimingRelationType type;

  /// Required for [TimingRelationType.separateFrom]; null otherwise.
  final int? minimumHours;

  /// Required for `beforeEvent` / `afterEvent`; null otherwise.
  final TimingEvent? event;
  final int? minimumMinutes;
  final int? maximumMinutes;

  bool get isBinary => type.isBinary;

  factory TimingRelation.fromJson(String ruleId, Map<String, dynamic> json) {
    final rawType = json['type'];
    if (rawType is! String || rawType.trim().isEmpty) {
      throw FormatException('$ruleId: timing_relation.type is required');
    }
    final type = TimingRelationType.fromString(rawType);

    int? intOrNull(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! int) {
        throw FormatException('$ruleId: timing_relation.$key must be an int');
      }
      return value;
    }

    final minimumHours = intOrNull('minimum_hours');
    final minimumMinutes = intOrNull('minimum_minutes');
    final maximumMinutes = intOrNull('maximum_minutes');

    TimingEvent? event;
    final rawEvent = json['event'];
    if (rawEvent != null) {
      if (rawEvent is! String) {
        throw FormatException('$ruleId: timing_relation.event must be a string');
      }
      event = TimingEvent.fromString(rawEvent);
    }

    switch (type) {
      case TimingRelationType.separateFrom:
      case TimingRelationType.separateFromMedications:
        if (minimumHours == null || minimumHours <= 0) {
          throw FormatException(
            '$ruleId: ${type.wireValue} requires a positive minimum_hours',
          );
        }
      case TimingRelationType.beforeEvent:
      case TimingRelationType.afterEvent:
        if (event == null) {
          throw FormatException('$ruleId: ${type.wireValue} requires an event');
        }
        if (minimumMinutes == null) {
          throw FormatException(
            '$ruleId: ${type.wireValue} requires minimum_minutes',
          );
        }
        if (maximumMinutes != null && maximumMinutes < minimumMinutes) {
          throw FormatException(
            '$ruleId: maximum_minutes must not be below minimum_minutes',
          );
        }
      case TimingRelationType.withFood:
      case TimingRelationType.emptyStomach:
      case TimingRelationType.consistentRelativeToPrescription:
        break;
    }

    return TimingRelation(
      type: type,
      minimumHours: minimumHours,
      event: event,
      minimumMinutes: minimumMinutes,
      maximumMinutes: maximumMinutes,
    );
  }
}

/// Where a rule displays.
///
/// Deliberately independent of [TimingActionability], [EvidenceLevel] and
/// [SourceAuthority]: "well evidenced" must never imply "urgent", and a
/// mechanism paper must never present like an FDA administration directive.
enum TimingCategory {
  /// Medication absorption or a meaningful supplement interaction. This is a
  /// safety signal, not an optimization.
  importantSeparation('important_separation'),

  /// How to take this product — food, empty stomach, formulation, or an
  /// event-relative instruction.
  howToTake('how_to_take'),

  /// Optional optimization. Renders only with an explicit clinician approval;
  /// failing to qualify for the other two is not sufficient.
  optional('optional');

  const TimingCategory(this.wireValue);

  final String wireValue;

  static TimingCategory fromString(String value) {
    final normalized = value.trim().toLowerCase();
    return TimingCategory.values.firstWhere(
      (category) => category.wireValue == normalized,
      orElse: () => throw FormatException('Unknown timing category: $value'),
    );
  }
}

/// Whether a rule about a single ingredient may fire inside a combination
/// product.
///
/// "Take iron on an empty stomach" is advice about an iron supplement. Applying
/// it to a 25-ingredient multivitamin that contains a trace of iron is how one
/// capsule ends up with two mutually exclusive instructions.
enum TimingAppliesTo {
  /// Only when the product is essentially this ingredient.
  standalone('standalone'),

  /// Any product containing the ingredient, including combination formulas.
  any('any');

  const TimingAppliesTo(this.wireValue);

  final String wireValue;

  static TimingAppliesTo fromString(String value) {
    final normalized = value.trim().toLowerCase();
    return TimingAppliesTo.values.firstWhere(
      (scope) => scope.wireValue == normalized,
      orElse: () => throw FormatException('Unknown applies_to: $value'),
    );
  }
}

/// What the user should actually do — independent of how certain the claim is.
enum TimingActionability {
  recommended('recommended'),
  optional('optional'),
  informational('informational');

  const TimingActionability(this.wireValue);

  final String wireValue;

  static TimingActionability fromString(String value) {
    final normalized = value.trim().toLowerCase();
    return TimingActionability.values.firstWhere(
      (item) => item.wireValue == normalized,
      orElse: () => throw FormatException('Unknown actionability: $value'),
    );
  }
}

/// What *kind* of evidence supports a rule, as distinct from how strong it is.
///
/// A drug label directing four-hour separation and a mechanism paper describing
/// a shared pathway can both be "established" while carrying entirely different
/// authority. Keeping these apart is what stops the second presenting like the
/// first.
enum SourceAuthority {
  fdaLabel('fda_label', 'FDA Label'),
  productLabel('product_label', 'Product Label'),
  guideline('guideline', 'Clinical Guideline'),
  systematicReview('systematic_review', 'Systematic Review'),
  clinicalStudy('clinical_study', 'Clinical Study'),
  mechanism('mechanism', 'Mechanism'),
  reference('reference', 'Reference');

  const SourceAuthority(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static SourceAuthority fromString(String value) {
    final normalized = value.trim().toLowerCase();
    return SourceAuthority.values.firstWhere(
      (item) => item.wireValue == normalized,
      orElse: () => throw FormatException('Unknown source_authority: $value'),
    );
  }
}

/// Publication gate. Only [verified] may render or enter the clinical-signal
/// aggregator.
///
/// There is deliberately no fourth state: a rule known to be wrong is either
/// suppressed ([needsRevision]) or removed ([rejected]) — never left active
/// pending a later pass.
enum TimingReviewStatus {
  verified('verified'),
  needsRevision('needs_revision'),
  rejected('rejected');

  const TimingReviewStatus(this.wireValue);

  final String wireValue;

  bool get isPublishable => this == verified;

  static TimingReviewStatus fromString(String value) {
    final normalized = value.trim().toLowerCase();
    return TimingReviewStatus.values.firstWhere(
      (item) => item.wireValue == normalized,
      orElse: () => throw FormatException('Unknown review_status: $value'),
    );
  }
}

/// One timing recommendation, resolved against the user's stack.
///
/// Produced by `TimingEvaluationService` when a verified rule matches. Guidance
/// is always attached to a physical stack row — users take bottles, not
/// nutrients — and the app never states when a prescribed medication is taken.
class TimingOptimization {
  /// The rule ID from timing_rules.json.
  final String ruleId;

  /// Display name of the first ingredient/medication involved.
  final String ingredient1;

  /// Display name of the second ingredient/medication, for binary relations.
  final String? ingredient2;

  /// User-facing advice text, in the pipeline's own words.
  final String advice;

  /// The structured relation this rule expresses.
  final TimingRelation relation;

  /// Where it displays.
  final TimingCategory category;

  /// What the user should do.
  final TimingActionability actionability;

  /// How certain the claim is.
  final EvidenceLevel evidenceLevel;

  /// What kind of evidence supports it.
  final SourceAuthority sourceAuthority;

  /// Impact on the stack safety score (negative = penalty).
  final int scoreImpact;

  /// Brief mechanism explanation (for "Learn more" expansion).
  final String? mechanism;

  /// Source URLs for the user to verify.
  final List<String> sourceUrls;

  /// Name of the product in the user's stack that triggered ingredient1.
  final String? product1Name;

  /// Stable local stack-row identity for [product1Name].
  ///
  /// Display names are not identifiers: two bottles may share a name, and fuzzy
  /// name matching can attach guidance to the wrong row.
  final String? product1StackEntryId;

  /// Name of the product in the user's stack that triggered ingredient2.
  final String? product2Name;

  /// Stable local stack-row identity for [product2Name].
  final String? product2StackEntryId;

  /// Whether a reviewed RxCUI on the rule matched a saved medication.
  final bool involvesMedication;

  /// True when the medication is the *first* side of the relation.
  ///
  /// The app constrains the supplement relative to the medication, never the
  /// other way round, so consumers need to know which row is the prescription.
  final bool medicationIsProduct1;

  const TimingOptimization({
    required this.ruleId,
    required this.ingredient1,
    required this.advice,
    required this.relation,
    required this.category,
    required this.actionability,
    required this.evidenceLevel,
    required this.sourceAuthority,
    required this.scoreImpact,
    this.ingredient2,
    this.mechanism,
    this.sourceUrls = const [],
    this.product1Name,
    this.product1StackEntryId,
    this.product2Name,
    this.product2StackEntryId,
    this.involvesMedication = false,
    this.medicationIsProduct1 = false,
  });

  /// Hours of separation required, for `separate_from` relations only.
  int? get separationHours => relation.minimumHours;

  bool get isSeparation =>
      relation.type == TimingRelationType.separateFrom ||
      relation.type == TimingRelationType.separateFromMedications;

  /// Display ordering: category dominates, then actionability, then evidence.
  ///
  /// Evidence breaks ties *within* a category — it never promotes a rule into a
  /// more prominent category, which is what kept "established" from meaning
  /// "urgent".
  int get displayPriority {
    final categoryRank = switch (category) {
      TimingCategory.importantSeparation => 3,
      TimingCategory.howToTake => 2,
      TimingCategory.optional => 1,
    };
    final actionabilityRank = switch (actionability) {
      TimingActionability.recommended => 2,
      TimingActionability.optional => 1,
      TimingActionability.informational => 0,
    };
    final evidenceBump = switch (evidenceLevel) {
      EvidenceLevel.established => 2,
      EvidenceLevel.probable => 1,
      EvidenceLevel.moderate => 1,
      EvidenceLevel.limited => 0,
      EvidenceLevel.theoretical => 0,
      EvidenceLevel.noData => -1,
      EvidenceLevel.ungraded => -1,
    };
    return categoryRank * 100 + actionabilityRank * 10 + evidenceBump;
  }
}
