import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';

enum TimingStackItemKind { supplement, medication }

/// One physical stack row presented to the timing evaluator.
///
/// The row id is the identity. [displayName] is attribution copy only, while
/// ingredient tags and RxCUIs are the reviewed matching inputs. Keeping them
/// together prevents parallel name-keyed maps from collapsing two products with
/// the same label.
class TimingStackItem {
  const TimingStackItem.supplement({
    required this.stackEntryId,
    required this.displayName,
    required this.ingredientTags,
  }) : assert(stackEntryId != ''),
       kind = TimingStackItemKind.supplement,
       medicationRxCuis = const {};

  const TimingStackItem.medication({
    required this.stackEntryId,
    required this.displayName,
    required this.medicationRxCuis,
  }) : assert(stackEntryId != ''),
       kind = TimingStackItemKind.medication,
       ingredientTags = const {};

  final String stackEntryId;
  final String displayName;
  final TimingStackItemKind kind;
  final Set<String> ingredientTags;
  final Set<String> medicationRxCuis;
}

/// Evaluates the user's stack against reviewed timing rules.
///
/// **Identity.** Rules carry pipeline-authored canonical tags — the same
/// identifiers written into `products_core.key_ingredient_tags`. There is no
/// app-side alias table and no name normalisation: a rule either names a tag the
/// catalog actually emits, or it matches nothing. The former alias map silently
/// invented tags (`vitamin_b12` when the catalog emits `vitamin_b12_cobalamin`),
/// which made rules look reachable while matching zero products.
///
/// **Publication.** Only `review_status: verified` rules are indexed at all.
/// A rule that has not been through source verification cannot reach a user by
/// any path, including the clinical-signal aggregator.
///
/// **Performance.** Index build O(R); evaluation O(S x rules-per-tag).
class TimingEvaluationService {
  TimingEvaluationService._({
    required this._rules,
    required this._ingredientIndex,
    required this._medicationIndex,
    required this.suppressedRuleCount,
  });

  /// Number of publishable (verified) timing rules loaded.
  int get ruleCount => _rules.length;

  /// Rules parsed successfully but withheld because they are not verified.
  ///
  /// Exposed so a release gate can assert the suppression count deliberately
  /// rather than discovering silently that everything stopped rendering.
  final int suppressedRuleCount;

  final List<_ParsedTimingRule> _rules;
  final Map<String, List<_IndexedRule>> _ingredientIndex;
  final Map<String, List<_IndexedRule>> _medicationIndex;

  /// Canonical tags referenced by any verified rule.
  ///
  /// Used to decide whether a bottle is "standalone" for a rule — see
  /// [_isStandaloneFor].
  late final Set<String> _timingRelevantTags = _ingredientIndex.keys.toSet();

  // ---------------------------------------------------------------------------
  // Factory
  // ---------------------------------------------------------------------------

  /// Build the service from the contents of timing_rules.json.
  ///
  /// Fails closed: a rule missing `category`, `applies_to`, `review_status`,
  /// `actionability`, `source_authority`, or `timing_relation` throws rather
  /// than defaulting. A malformed artifact must surface as unavailable, never as
  /// a clean result.
  factory TimingEvaluationService.fromJson(Map<String, dynamic> json) {
    final rawList = json['timing_rules'];
    if (rawList is! List) {
      throw const FormatException('timing_rules must be a JSON array');
    }
    final metadata = json['_metadata'];
    if (metadata is Map && metadata['total_entries'] is int) {
      final declared = metadata['total_entries'] as int;
      if (declared != rawList.length) {
        throw FormatException(
          'timing_rules metadata declares $declared entries, '
          'but ${rawList.length} were provided',
        );
      }
    }

    final parsed = <_ParsedTimingRule>[];
    for (final raw in rawList) {
      if (raw is! Map) {
        throw const FormatException('each timing rule must be a JSON object');
      }
      parsed.add(_ParsedTimingRule.fromJson(Map<String, dynamic>.from(raw)));
    }

    final publishable = parsed
        .where((rule) => rule.reviewStatus.isPublishable)
        .toList(growable: false);

    final ingredientIndex = <String, List<_IndexedRule>>{};
    final medicationIndex = <String, List<_IndexedRule>>{};

    for (final rule in publishable) {
      if (rule.ingredient1Rxcuis.isNotEmpty) {
        for (final rxcui in rule.ingredient1Rxcuis) {
          medicationIndex
              .putIfAbsent(rxcui, () => [])
              .add(_IndexedRule(rule: rule, isIngredient1: true));
        }
      } else {
        for (final tag in rule.ingredient1Tags) {
          ingredientIndex
              .putIfAbsent(tag, () => [])
              .add(_IndexedRule(rule: rule, isIngredient1: true));
        }
      }

      // Only a binary relation has a second matchable side. Unary relations
      // encode their context in `timing_relation`, so there is no pseudo
      // ingredient ("food", "sleep") to filter out any more.
      if (!rule.relation.isBinary) continue;

      if (rule.ingredient2Rxcuis.isNotEmpty) {
        for (final rxcui in rule.ingredient2Rxcuis) {
          medicationIndex
              .putIfAbsent(rxcui, () => [])
              .add(_IndexedRule(rule: rule, isIngredient1: false));
        }
      } else {
        for (final tag in rule.ingredient2Tags) {
          ingredientIndex
              .putIfAbsent(tag, () => [])
              .add(_IndexedRule(rule: rule, isIngredient1: false));
        }
      }
    }

    return TimingEvaluationService._(
      rules: publishable,
      ingredientIndex: ingredientIndex,
      medicationIndex: medicationIndex,
      suppressedRuleCount: parsed.length - publishable.length,
    );
  }

  // ---------------------------------------------------------------------------
  // Evaluation
  // ---------------------------------------------------------------------------

  /// Evaluate the user's current stack and return timing optimizations.
  List<TimingOptimization> evaluateStack({
    required List<TimingStackItem> stackItems,
    Map<String, double> ingredientDosesMg = const {},
  }) {
    final results = <String, TimingOptimization>{};

    void addResult(
      _ParsedTimingRule rule, {
      required TimingStackItem product1,
      TimingStackItem? product2,
      required bool medicationIsProduct1,
    }) {
      final result = _buildResult(
        rule,
        product1: product1,
        product2: product2,
        medicationIsProduct1: medicationIsProduct1,
      );
      results[_physicalResultKey(result)] = result;
    }

    final supplements = stackItems
        .where((item) => item.kind == TimingStackItemKind.supplement)
        .toList(growable: false);
    final medications = stackItems
        .where((item) => item.kind == TimingStackItemKind.medication)
        .toList(growable: false);

    final tagToProducts = <String, List<TimingStackItem>>{};
    for (final item in supplements) {
      for (final tag in item.ingredientTags) {
        tagToProducts.putIfAbsent(tag, () => []).add(item);
      }
    }

    // --- Pass 1: supplement-side rules ---
    for (final tag in tagToProducts.keys) {
      final matchingRules = _ingredientIndex[tag];
      if (matchingRules == null) continue;

      for (final indexed in matchingRules) {
        final rule = indexed.rule;
        if (!_passesDoseGate(rule, ingredientDosesMg)) continue;

        if (!rule.relation.isBinary) {
          // Unary: constrains the bottle carrying this tag, on its own.
          for (final product in tagToProducts[tag]!) {
            if (!_isStandaloneGatePassed(rule, product, tag)) continue;
            addResult(rule, product1: product, medicationIsProduct1: false);
          }
          continue;
        }

        final otherTags = indexed.isIngredient1
            ? rule.ingredient2Tags
            : rule.ingredient1Tags;
        for (final otherTag in otherTags) {
          final otherProducts = tagToProducts[otherTag];
          if (otherProducts == null) continue;
          for (final first in tagToProducts[tag]!) {
            for (final second in otherProducts) {
              // A rule cannot separate two nutrients inside one bottle.
              // Compare row identity, never names.
              if (first.stackEntryId == second.stackEntryId) continue;
              addResult(
                rule,
                product1: indexed.isIngredient1 ? first : second,
                product2: indexed.isIngredient1 ? second : first,
                medicationIsProduct1: false,
              );
            }
          }
        }
      }
    }

    // --- Pass 2: medication-side rules ---
    for (final medication in medications) {
      for (final rxcui in medication.medicationRxCuis) {
        final matchingRules = _medicationIndex[rxcui];
        if (matchingRules == null) continue;

        for (final indexed in matchingRules) {
          final rule = indexed.rule;
          if (!_passesDoseGate(rule, ingredientDosesMg)) continue;

          if (!rule.relation.isBinary) {
            // A unary rule about a prescribed medication would be an
            // instruction about how to take that prescription. That belongs to
            // the prescriber, so it is never emitted.
            continue;
          }

          final supplementTags = indexed.isIngredient1
              ? rule.ingredient2Tags
              : rule.ingredient1Tags;
          for (final tag in supplementTags) {
            final supplementProducts = tagToProducts[tag];
            if (supplementProducts == null) continue;
            for (final supplement in supplementProducts) {
              addResult(
                rule,
                product1: indexed.isIngredient1 ? medication : supplement,
                product2: indexed.isIngredient1 ? supplement : medication,
                medicationIsProduct1: indexed.isIngredient1,
              );
            }
          }
        }
      }
    }

    final sorted = results.values.toList()
      ..sort((a, b) {
        final priority = b.displayPriority.compareTo(a.displayPriority);
        return priority != 0 ? priority : a.ruleId.compareTo(b.ruleId);
      });

    // Collapse semantically identical tips. Several rule ids can describe the
    // same user action for the same bottle — a product carrying vitamin D and
    // vitamin K trips two "with food" rules, but the user is told once.
    final deduped = <TimingOptimization>[];
    final seen = <String>{};
    for (final opt in sorted) {
      if (seen.add(_semanticKey(opt))) deduped.add(opt);
    }
    return deduped;
  }

  /// Most ingredient tags a bottle may carry and still be "essentially this
  /// ingredient": the named one plus at most one companion.
  ///
  /// A composition fact about the product, deliberately independent of how many
  /// rules happen to be verified — see [_isStandaloneFor].
  static const _maxStandaloneIngredientTags = 2;

  /// Whether a `standalone` rule may fire for [product].
  ///
  /// "Standalone" means the instruction is unambiguous for this bottle. O.N.E.
  /// Multivitamin carries alpha-lipoic acid alongside vitamins A/D/E and zinc;
  /// "take on an empty stomach" is advice about an ALA supplement, not about a
  /// 25-ingredient capsule containing a trace of it.
  bool _isStandaloneGatePassed(
    _ParsedTimingRule rule,
    TimingStackItem product,
    String matchedTag,
  ) {
    if (rule.appliesTo == TimingAppliesTo.any) return true;
    return _isStandaloneFor(product, matchedTag);
  }

  /// Two independent conditions, both required.
  ///
  /// The rule-coverage half alone was unsafe: it asked whether the matched tag
  /// was the only one on the bottle that any VERIFIED rule speaks to, which
  /// silently loosens as rules are retired. When the vitamin A, K and zinc
  /// rules were rejected, `vitamin_e` became the only timing-relevant tag on a
  /// 25-ingredient multivitamin — so the multivitamin began qualifying as a
  /// standalone vitamin E supplement. A gate whose strictness depends on how
  /// much of the corpus survived review is not a gate.
  ///
  /// The composition half fixes that: a bottle listing many actives is not
  /// "essentially this ingredient" no matter what the rule set looks like.
  /// It is a bounded app-side heuristic, and the honest long-term answer is a
  /// pipeline-authored formulation flag.
  bool _isStandaloneFor(TimingStackItem product, String matchedTag) {
    if (product.ingredientTags.length > _maxStandaloneIngredientTags) {
      return false;
    }
    for (final tag in product.ingredientTags) {
      if (tag == matchedTag) continue;
      if (_timingRelevantTags.contains(tag)) return false;
    }
    return true;
  }

  /// Identifies the *user-facing action* of a tip, independent of which rule
  /// produced it. Single-product tips key on (product, relation); pair tips key
  /// on the unordered product pair + relation.
  static String _semanticKey(TimingOptimization opt) {
    final type = opt.relation.type.wireValue;
    final p1 = opt.product1StackEntryId ?? opt.product1Name ?? opt.ingredient1;
    final p2 = opt.product2StackEntryId ?? opt.product2Name;
    if (p2 == null) return '$type|$p1';
    final pair = [p1, p2]..sort();
    return '$type|${pair.join('|')}';
  }

  /// Deduplicates the same rule reached through both indexed sides, without
  /// collapsing distinct physical stack rows.
  static String _physicalResultKey(TimingOptimization opt) {
    final first =
        opt.product1StackEntryId ?? opt.product1Name ?? opt.ingredient1;
    final second =
        opt.product2StackEntryId ?? opt.product2Name ?? opt.ingredient2 ?? '';
    return '${opt.ruleId}|$first|$second';
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  TimingOptimization _buildResult(
    _ParsedTimingRule rule, {
    required TimingStackItem product1,
    TimingStackItem? product2,
    required bool medicationIsProduct1,
  }) {
    return TimingOptimization(
      ruleId: rule.id,
      ingredient1: rule.ingredient1Display,
      ingredient2: rule.ingredient2Display,
      advice: rule.advice,
      relation: rule.relation,
      category: rule.category,
      actionability: rule.actionability,
      evidenceLevel: rule.evidenceLevel,
      sourceAuthority: rule.sourceAuthority,
      scoreImpact: rule.scoreImpact,
      mechanism: rule.mechanism,
      sourceUrls: rule.sourceUrls,
      product1Name: product1.displayName,
      product1StackEntryId: product1.stackEntryId,
      product2Name: product2?.displayName,
      product2StackEntryId: product2?.stackEntryId,
      involvesMedication: rule.involvesMedication,
      medicationIsProduct1: medicationIsProduct1,
    );
  }

  /// True if [rule]'s optional dose gate is satisfied (or absent).
  ///
  /// Dose-conditional copy is suppressed when the relevant total is unknown:
  /// this must never imply a threshold was crossed without a measured total.
  bool _passesDoseGate(_ParsedTimingRule rule, Map<String, double> doses) {
    final tag = rule.minDoseTag;
    final threshold = rule.minDoseMg;
    if (tag == null || threshold == null) return true;
    if (doses.isEmpty) return false;
    final dose = doses[tag];
    if (dose == null) return false;
    return dose >= threshold;
  }
}

// ---------------------------------------------------------------------------
// Internal models
// ---------------------------------------------------------------------------

class _ParsedTimingRule {
  final String id;
  final String ingredient1Display;
  final String? ingredient2Display;
  final Set<String> ingredient1Tags;
  final Set<String> ingredient2Tags;
  final Set<String> ingredient1Rxcuis;
  final Set<String> ingredient2Rxcuis;
  final TimingRelation relation;
  final TimingCategory category;
  final TimingAppliesTo appliesTo;
  final TimingActionability actionability;
  final TimingReviewStatus reviewStatus;
  final SourceAuthority sourceAuthority;
  final String advice;
  final String? mechanism;
  final int scoreImpact;
  final EvidenceLevel evidenceLevel;
  final List<String> sourceUrls;

  /// Optional dose gate, keyed on a canonical tag.
  final String? minDoseTag;
  final double? minDoseMg;

  _ParsedTimingRule({
    required this.id,
    required this.ingredient1Display,
    required this.ingredient2Display,
    required this.ingredient1Tags,
    required this.ingredient2Tags,
    required this.ingredient1Rxcuis,
    required this.ingredient2Rxcuis,
    required this.relation,
    required this.category,
    required this.appliesTo,
    required this.actionability,
    required this.reviewStatus,
    required this.sourceAuthority,
    required this.advice,
    required this.scoreImpact,
    required this.evidenceLevel,
    this.mechanism,
    this.sourceUrls = const [],
    this.minDoseTag,
    this.minDoseMg,
  });

  factory _ParsedTimingRule.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('timing rule requires non-empty $key');
      }
      return value.trim();
    }

    final id = requiredString('id');

    String requiredEnumString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('$id: $key is required');
      }
      return value.trim();
    }

    Set<String> tags(String key) {
      final raw = json[key];
      if (raw == null) return const {};
      if (raw is! List ||
          raw.any((v) => v is! String || v.trim().isEmpty)) {
        throw FormatException('$id: $key must be a list of canonical tags');
      }
      return raw.cast<String>().map((v) => v.trim()).toSet();
    }

    Set<String> rxcuis(String key) {
      final raw = json[key];
      if (raw == null) return const {};
      if (raw is! List ||
          raw.any(
            (value) =>
                value is! String ||
                value.trim().isEmpty ||
                !RegExp(r'^\d+$').hasMatch(value.trim()),
          )) {
        throw FormatException('$id: $key must contain RxCUI strings');
      }
      return raw.cast<String>().map((value) => value.trim()).toSet();
    }

    final rawRelation = json['timing_relation'];
    if (rawRelation is! Map) {
      throw FormatException('$id: timing_relation is required');
    }
    final relation = TimingRelation.fromJson(
      id,
      Map<String, dynamic>.from(rawRelation),
    );

    final category = TimingCategory.fromString(requiredEnumString('category'));
    final appliesTo = TimingAppliesTo.fromString(
      requiredEnumString('applies_to'),
    );
    final reviewStatus = TimingReviewStatus.fromString(
      requiredEnumString('review_status'),
    );
    final actionability = TimingActionability.fromString(
      requiredEnumString('actionability'),
    );
    final sourceAuthority = SourceAuthority.fromString(
      requiredEnumString('source_authority'),
    );

    // An "optional optimization" must be positively approved. Failing to
    // qualify for the other two categories is not an argument for showing it.
    if (category == TimingCategory.optional &&
        reviewStatus == TimingReviewStatus.verified &&
        json['clinician_approved'] != true) {
      throw FormatException(
        '$id: category=optional requires clinician_approved: true',
      );
    }

    // The schema migration had to give every rule a parseable relation. Where
    // the legacy `take_together` had no equivalent, it parked `with_food` —
    // a value the pipeline never authored and which does not represent the
    // original claim. Such a rule must be structurally incapable of shipping:
    // marking it verified without first re-authoring the relation would
    // publish a placeholder as clinical guidance.
    if (json['_relation_is_migration_placeholder'] == true &&
        reviewStatus == TimingReviewStatus.verified) {
      throw FormatException(
        '$id: a migration-placeholder relation cannot be verified. Re-author '
        'timing_relation from the source before promoting this rule.',
      );
    }

    final ingredient1Tags = tags('ingredient1_tags');
    final ingredient2Tags = tags('ingredient2_tags');
    final ingredient1Rxcuis = rxcuis('ingredient1_rxcuis');
    final ingredient2Rxcuis = rxcuis('ingredient2_rxcuis');

    if (ingredient1Tags.isEmpty && ingredient1Rxcuis.isEmpty) {
      throw FormatException(
        '$id: needs ingredient1_tags or ingredient1_rxcuis',
      );
    }
    if (relation.isBinary &&
        ingredient2Tags.isEmpty &&
        ingredient2Rxcuis.isEmpty) {
      throw FormatException(
        '$id: a ${relation.type.wireValue} relation needs a second identity',
      );
    }
    if (!relation.isBinary &&
        (ingredient2Tags.isNotEmpty || ingredient2Rxcuis.isNotEmpty)) {
      throw FormatException(
        '$id: ${relation.type.wireValue} is unary and must not carry a '
        'second identity',
      );
    }

    if (json['score_impact'] is! int) {
      throw FormatException('$id: score_impact must be an integer');
    }

    // A dose gate that fails to parse must not silently become a rule that
    // always fires. Either it gates, or the artifact is rejected.
    String? minDoseTag;
    double? minDoseMg;
    final minDose = json['min_dose'];
    if (minDose != null) {
      if (minDose is! Map) {
        throw FormatException('$id: min_dose must be an object');
      }
      final tag = minDose['tag'];
      final mg = minDose['mg'];
      if (tag is! String || tag.trim().isEmpty || mg is! num) {
        throw FormatException(
          '$id: min_dose requires a canonical `tag` and numeric `mg`',
        );
      }
      minDoseTag = tag.trim();
      minDoseMg = mg.toDouble();
    }

    final sources = json.safeMapList('sources');
    final sourceUrls = sources
        .map((s) => s.safeString('url'))
        .where((url) => url.isNotEmpty)
        .toList(growable: false);

    final evidenceStr = requiredEnumString('evidence_level');
    // "possible" predates the shared evidence vocabulary; map it to the
    // weakest graded tier rather than inventing a stronger one.
    final mappedEvidence = evidenceStr == 'possible'
        ? 'theoretical'
        : evidenceStr;

    final ingredient2Display = json['ingredient2'];
    if (ingredient2Display != null && ingredient2Display is! String) {
      throw FormatException('$id: ingredient2 must be a string when present');
    }

    return _ParsedTimingRule(
      id: id,
      ingredient1Display: requiredString('ingredient1'),
      ingredient2Display: (ingredient2Display as String?)?.trim(),
      ingredient1Tags: ingredient1Tags,
      ingredient2Tags: ingredient2Tags,
      ingredient1Rxcuis: ingredient1Rxcuis,
      ingredient2Rxcuis: ingredient2Rxcuis,
      relation: relation,
      category: category,
      appliesTo: appliesTo,
      actionability: actionability,
      reviewStatus: reviewStatus,
      sourceAuthority: sourceAuthority,
      advice: requiredString('advice'),
      mechanism: json['mechanism'] is String
          ? json['mechanism'] as String
          : null,
      scoreImpact: json.safeInt('score_impact'),
      evidenceLevel: EvidenceLevel.fromString(mappedEvidence),
      sourceUrls: sourceUrls,
      minDoseTag: minDoseTag,
      minDoseMg: minDoseMg,
    );
  }

  bool get involvesMedication =>
      ingredient1Rxcuis.isNotEmpty || ingredient2Rxcuis.isNotEmpty;
}

class _IndexedRule {
  final _ParsedTimingRule rule;

  /// True if this rule was indexed via its ingredient1 side.
  final bool isIngredient1;

  const _IndexedRule({required this.rule, required this.isIngredient1});
}
