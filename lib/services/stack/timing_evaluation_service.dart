import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';

enum TimingStackItemKind { supplement, medication }

/// One physical stack row presented to the timing evaluator.
///
/// The row id is the identity. [displayName] is attribution copy only, while
/// ingredient tags and RxCUIs are the reviewed matching inputs. Keeping them
/// together prevents parallel name-keyed maps from collapsing two products
/// with the same label.
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

/// Evaluates the user's supplement + medication stack against timing rules
/// and produces actionable timing advice.
///
/// **Design:**
///
/// At load time, builds an inverted index: `ingredient_key → [rules]` so
/// that evaluating a stack of N items requires only O(N) lookups instead
/// of O(N × R) brute-force comparisons. Each ingredient in the stack is
/// looked up once; matching rules are collected and deduplicated by rule ID.
///
/// **Matching strategy:**
///
/// Supplements are matched via their `key_ingredient_tags` canonical IDs
/// (e.g., "iron", "calcium", "vitamin_d") — the same identifiers the
/// pipeline writes into `products_core`.
///
/// Medications are matched only through reviewed RxCUIs authored on each
/// timing rule. Display names are never used as clinical identity.
///
/// **Performance:**
///
/// Index build: O(R) where R = number of rules.
/// Stack evaluation: O(S × avg_rules_per_ingredient) where S = stack size.
/// Runtime scales with indexed matches rather than scanning the full rule set
/// for every stack item.
class TimingEvaluationService {
  TimingEvaluationService._({
    required this._rules,
    required this._ingredientIndex,
    required this._medicationIndex,
  });

  /// Number of timing rules loaded.
  int get ruleCount => _rules.length;

  /// All parsed timing rules (internal).
  final List<_ParsedTimingRule> _rules;

  /// ingredient_key → list of rules that reference this ingredient.
  final Map<String, List<_IndexedRule>> _ingredientIndex;

  /// RxCUI → list of rules that reference this medication.
  final Map<String, List<_IndexedRule>> _medicationIndex;

  /// Supplement ingredient keys that map to timing rule ingredient names.
  /// Most are 1:1 but some need aliases (e.g., timing says "omega-3",
  /// product tags say "omega_3").
  static const _ingredientAliases = <String, List<String>>{
    'iron': ['iron'],
    'calcium': ['calcium'],
    'calcium carbonate': ['calcium_carbonate'],
    'zinc': ['zinc'],
    'copper': ['copper'],
    'magnesium': ['magnesium'],
    'vitamin c': ['vitamin_c'],
    'vitamin d': ['vitamin_d'],
    'vitamin e': ['vitamin_e'],
    'vitamin k': ['vitamin_k'],
    'vitamin b12': ['vitamin_b12'],
    'vitamin b complex': [
      'vitamin_b1',
      'vitamin_b2',
      'vitamin_b3',
      'vitamin_b5',
      'vitamin_b6',
      'vitamin_b12',
    ],
    'folate': ['folate', 'vitamin_b9'],
    'omega-3': ['omega_3', 'fish_oil', 'epa', 'dha'],
    'coq10': ['coq10'],
    'turmeric': ['turmeric', 'curcumin'],
    'probiotics': ['probiotics', 'probiotic'],
    'melatonin': ['melatonin'],
    'green tea extract': ['green_tea_extract', 'egcg'],
    'caffeine': ['caffeine', 'guarana'],
    'fiber': ['fiber', 'psyllium', 'inulin'],
    'nac': ['nac', 'n_acetyl_cysteine'],
    'alpha-lipoic acid': ['alpha_lipoic_acid'],
    'collagen peptides': ['collagen'],
    'quercetin': ['quercetin'],
    'bromelain': ['bromelain'],
    'ashwagandha': ['ashwagandha'],
    'l-theanine': ['l_theanine'],
    'berberine': ['berberine'],
    'soy protein': ['soy', 'soy_protein', 'soy_isoflavones'],
  };

  // ---------------------------------------------------------------------------
  // Factory
  // ---------------------------------------------------------------------------

  /// Build the service from raw JSON (the contents of timing_rules.json).
  ///
  /// Call once at app startup or when the reference data cache refreshes.
  /// The returned instance is immutable and safe to share across isolates.
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

    // Build inverted indexes.
    final ingredientIndex = <String, List<_IndexedRule>>{};
    final medicationIndex = <String, List<_IndexedRule>>{};

    for (final rule in parsed) {
      final i1Norm = rule.ingredient1Normalized;
      final i2Norm = rule.ingredient2Normalized;

      // Index ingredient1 side.
      if (rule.ingredient1Rxcuis.isNotEmpty) {
        for (final rxcui in rule.ingredient1Rxcuis) {
          _addToMedIndex(medicationIndex, rxcui, rule, isIngredient1: true);
        }
      } else {
        _addToIngredientIndex(
          ingredientIndex,
          i1Norm,
          rule,
          isIngredient1: true,
        );
      }

      // Index ingredient2 side (skip non-matchable context like "food",
      // "sleep", "dietary fat", "medications", "melatonin production").
      if (!_isContextOnly(i2Norm)) {
        if (rule.ingredient2Rxcuis.isNotEmpty) {
          for (final rxcui in rule.ingredient2Rxcuis) {
            _addToMedIndex(medicationIndex, rxcui, rule, isIngredient1: false);
          }
        } else {
          _addToIngredientIndex(
            ingredientIndex,
            i2Norm,
            rule,
            isIngredient1: false,
          );
        }
      }
    }

    return TimingEvaluationService._(
      rules: parsed,
      ingredientIndex: ingredientIndex,
      medicationIndex: medicationIndex,
    );
  }

  // ---------------------------------------------------------------------------
  // Evaluation
  // ---------------------------------------------------------------------------

  /// Evaluate the user's current stack and return timing optimizations.
  ///
  /// [stackItems] keeps each physical row's stable id beside its display name
  /// and reviewed matching identities. Missing medication identity never
  /// falls back to text matching.
  ///
  /// Returns a deduplicated, priority-sorted list of timing advice.
  List<TimingOptimization> evaluateStack({
    required List<TimingStackItem> stackItems,
    Map<String, double> ingredientDosesMg = const {},
  }) {
    final results = <String, TimingOptimization>{};

    void addResult(
      _ParsedTimingRule rule, {
      required TimingStackItem product1,
      TimingStackItem? product2,
    }) {
      final result = _buildResult(rule, product1: product1, product2: product2);
      results[_physicalResultKey(result)] = result;
    }

    final supplements = stackItems
        .where((item) => item.kind == TimingStackItemKind.supplement)
        .toList(growable: false);
    final medications = stackItems
        .where((item) => item.kind == TimingStackItemKind.medication)
        .toList(growable: false);

    // Collect all ingredient tags across the entire stack into a
    // tag → [physical stack rows] map for O(1) membership checks.
    final tagToProducts = <String, List<TimingStackItem>>{};
    for (final item in supplements) {
      for (final tag in item.ingredientTags) {
        tagToProducts.putIfAbsent(tag, () => []).add(item);
      }
    }

    // --- Pass 1: Supplement × Supplement timing rules ---
    // For each tag in the stack, check if any rule references it.
    for (final tag in tagToProducts.keys) {
      final matchingRules = _ingredientIndex[tag];
      if (matchingRules == null) continue;

      for (final indexed in matchingRules) {
        if (!_passesDoseGate(indexed.rule, ingredientDosesMg)) continue;

        // Find the OTHER side of this rule.
        final otherIngredient = indexed.isIngredient1
            ? indexed.rule.ingredient2Normalized
            : indexed.rule.ingredient1Normalized;

        // Is the other side a context-only value (food, sleep, etc.)?
        // If so, this is a single-ingredient timing rule — always fire.
        if (_isContextOnly(otherIngredient)) {
          if (otherIngredient == 'medications' && medications.isEmpty) {
            continue;
          }
          final products = tagToProducts[tag]!;
          for (final product in products) {
            addResult(indexed.rule, product1: product);
          }
          continue;
        }

        // Check if the other ingredient is also in the stack.
        final otherAliases = _resolveAliases(otherIngredient);
        for (final alias in otherAliases) {
          if (tagToProducts.containsKey(alias)) {
            final product1Rows = tagToProducts[tag]!;
            final product2Rows = tagToProducts[alias]!;
            for (final first in product1Rows) {
              for (final second in product2Rows) {
                // A rule cannot separate or join nutrients inside one
                // physical bottle. Compare row identity, never names.
                if (first.stackEntryId == second.stackEntryId) continue;
                addResult(
                  indexed.rule,
                  product1: indexed.isIngredient1 ? first : second,
                  product2: indexed.isIngredient1 ? second : first,
                );
              }
            }
            break;
          }
        }
      }
    }

    // --- Pass 2: Medication × Supplement timing rules ---
    for (final medication in medications) {
      for (final rxcui in medication.medicationRxCuis) {
        final matchingRules = _medicationIndex[rxcui];
        if (matchingRules == null) continue;

        for (final indexed in matchingRules) {
          if (!_passesDoseGate(indexed.rule, ingredientDosesMg)) continue;

          // Find the supplement side of the rule.
          final suppIngredient = indexed.isIngredient1
              ? indexed.rule.ingredient2Normalized
              : indexed.rule.ingredient1Normalized;

          if (_isContextOnly(suppIngredient)) {
            // Medication-only rule (e.g., "take levothyroxine on empty
            // stomach") — always fire if the medication is in the stack.
            addResult(indexed.rule, product1: medication);
            continue;
          }

          // Check if the supplement side is in the stack.
          final suppAliases = _resolveAliases(suppIngredient);
          for (final alias in suppAliases) {
            if (tagToProducts.containsKey(alias)) {
              final suppProducts = tagToProducts[alias]!;
              for (final supplement in suppProducts) {
                addResult(
                  indexed.rule,
                  product1: indexed.isIngredient1 ? medication : supplement,
                  product2: indexed.isIngredient1 ? supplement : medication,
                );
              }
              break;
            }
          }
        }
      }
    }

    // Sort by priority (medication interactions first, then separations,
    // then other types).
    final sorted = results.values.toList()
      ..sort((a, b) {
        final priority = b.displayPriority.compareTo(a.displayPriority);
        return priority != 0 ? priority : a.ruleId.compareTo(b.ruleId);
      });

    // Collapse semantically-identical tips. Several distinct rule IDs can
    // describe the SAME user action for the SAME product(s) — e.g. a product
    // carrying both vitamin D and vitamin K trips two "take with food" rules,
    // but the user only needs to be told once to take that product with a
    // meal. Physical-result dedup preserves different bottles, while this
    // semantic pass keys on the resolved product(s) + rule type. Sorted-first
    // wins, so the highest-priority / strongest-evidence variant is kept.
    final deduped = <TimingOptimization>[];
    final seenSemanticKeys = <String>{};
    for (final opt in sorted) {
      if (seenSemanticKeys.add(_semanticKey(opt))) deduped.add(opt);
    }

    return deduped;
  }

  /// A key that identifies the *user-facing action* of a tip, independent of
  /// which rule produced it. Single-product tips (take with food, time of
  /// day, empty stomach) key on (product, type); pair tips key on the
  /// unordered product pair + type so "A & B separate" and "B & A separate"
  /// collapse to one.
  static String _semanticKey(TimingOptimization opt) {
    final type = opt.ruleType.name;
    final p1 = opt.product1StackEntryId ?? opt.product1Name ?? opt.ingredient1;
    final p2 = opt.product2StackEntryId ?? opt.product2Name;
    if (p2 == null) return '$type|$p1';
    final pair = [p1, p2]..sort();
    return '$type|${pair.join('|')}';
  }

  /// Deduplicates the same rule reached through multiple aliases or both
  /// indexed sides, without collapsing distinct physical stack rows.
  static String _physicalResultKey(TimingOptimization opt) {
    final first =
        opt.product1StackEntryId ?? opt.product1Name ?? opt.ingredient1;
    final second =
        opt.product2StackEntryId ?? opt.product2Name ?? opt.ingredient2;
    return '${opt.ruleId}|$first|$second';
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  TimingOptimization _buildResult(
    _ParsedTimingRule rule, {
    TimingStackItem? product1,
    TimingStackItem? product2,
  }) {
    return TimingOptimization(
      ruleId: rule.id,
      ingredient1: rule.ingredient1Display,
      ingredient2: rule.ingredient2Display,
      advice: rule.advice,
      ruleType: rule.ruleType,
      separationHours: rule.separationHours,
      scoreImpact: rule.scoreImpact,
      evidenceLevel: rule.evidenceLevel,
      mechanism: rule.mechanism,
      sourceUrls: rule.sourceUrls,
      product1Name: product1?.displayName,
      product1StackEntryId: product1?.stackEntryId,
      product2Name: product2?.displayName,
      product2StackEntryId: product2?.stackEntryId,
      involvesMedication: rule.involvesMedication,
      allowedDailySlots: rule.allowedDailySlots,
      dailyPlanEligible: rule.dailyPlanEligible,
    );
  }

  /// Resolve a timing rule ingredient name to all possible canonical tag
  /// values that might appear in a product's key_ingredient_tags.
  List<String> _resolveAliases(String normalizedIngredient) {
    final aliases = _ingredientAliases[normalizedIngredient];
    if (aliases != null) return aliases;
    // Fallback: the normalized name itself might be a direct tag match.
    return [normalizedIngredient.replaceAll(' ', '_').replaceAll('-', '_')];
  }

  /// True if [rule]'s optional dose gate is satisfied (or absent).
  ///
  /// Dose-conditional copy is suppressed when the relevant total is unknown.
  /// The caller separately reports incomplete nutrient coverage; this method
  /// must never imply that a threshold was crossed without a measured total.
  bool _passesDoseGate(_ParsedTimingRule rule, Map<String, double> doses) {
    final ingredient = rule.minDoseIngredient;
    final threshold = rule.minDoseMg;
    if (ingredient == null || threshold == null) return true;
    if (doses.isEmpty) return false;
    for (final alias in _resolveAliases(ingredient)) {
      final dose = doses[alias];
      if (dose != null) return dose >= threshold;
    }
    return false;
  }

  /// Context-only ingredients that don't correspond to a real stack item.
  /// These are the "other side" of single-ingredient timing rules like
  /// "take CoQ10 with food" where ingredient2 = "dietary fat".
  static bool _isContextOnly(String normalized) {
    const contextTerms = {
      'food',
      'dietary fat',
      'sleep',
      'melatonin production',
      'medications',
    };
    return contextTerms.contains(normalized);
  }

  static void _addToIngredientIndex(
    Map<String, List<_IndexedRule>> index,
    String ingredientName,
    _ParsedTimingRule rule, {
    required bool isIngredient1,
  }) {
    final aliases = _ingredientAliases[ingredientName];
    final keys =
        aliases ?? [ingredientName.replaceAll(' ', '_').replaceAll('-', '_')];
    for (final key in keys) {
      index
          .putIfAbsent(key, () => [])
          .add(_IndexedRule(rule: rule, isIngredient1: isIngredient1));
    }
  }

  static void _addToMedIndex(
    Map<String, List<_IndexedRule>> index,
    String rxcui,
    _ParsedTimingRule rule, {
    required bool isIngredient1,
  }) {
    index
        .putIfAbsent(rxcui, () => [])
        .add(_IndexedRule(rule: rule, isIngredient1: isIngredient1));
  }
}

// ---------------------------------------------------------------------------
// Internal models
// ---------------------------------------------------------------------------

class _ParsedTimingRule {
  final String id;
  final String ingredient1Display;
  final String ingredient2Display;
  final String ingredient1Normalized;
  final String ingredient2Normalized;
  final TimingRuleType ruleType;
  final String advice;
  final String? mechanism;
  final int? separationHours;
  final int scoreImpact;
  final EvidenceLevel evidenceLevel;
  final List<String> sourceUrls;
  final Set<String> ingredient1Rxcuis;
  final Set<String> ingredient2Rxcuis;
  final Set<DailySlot> allowedDailySlots;
  final bool dailyPlanEligible;

  /// Optional dose gate: the rule only fires when [minDoseIngredient]'s total
  /// stack dose is at or above [minDoseMg]. Both null = no gate (always fire).
  /// e.g. iron↔zinc competition only matters at iron ≥ 25 mg fasting.
  final String? minDoseIngredient;
  final double? minDoseMg;

  _ParsedTimingRule({
    required this.id,
    required this.ingredient1Display,
    required this.ingredient2Display,
    required this.ingredient1Normalized,
    required this.ingredient2Normalized,
    required this.ruleType,
    required this.advice,
    this.mechanism,
    this.separationHours,
    required this.scoreImpact,
    required this.evidenceLevel,
    this.sourceUrls = const [],
    this.ingredient1Rxcuis = const {},
    this.ingredient2Rxcuis = const {},
    this.allowedDailySlots = const {},
    this.dailyPlanEligible = true,
    this.minDoseIngredient,
    this.minDoseMg,
  });

  factory _ParsedTimingRule.fromJson(Map<String, dynamic> json) {
    final sources = json
        .safeMapList('sources')
        .map((s) => s.safeString('url'))
        .where((url) => url.isNotEmpty)
        .toList(growable: false);

    final evidenceStr = json.safeString('evidence_level', 'possible');
    // Map "possible" → "theoretical" since EvidenceLevel enum doesn't have "possible"
    final mappedEvidence = evidenceStr == 'possible'
        ? 'theoretical'
        : evidenceStr;

    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('timing rule requires non-empty $key');
      }
      return value.trim();
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
        throw FormatException('$key must contain RxCUI strings');
      }
      return raw.cast<String>().map((value) => value.trim()).toSet();
    }

    Set<DailySlot> dailySlots() {
      final raw = json['daily_slots'];
      if (raw == null) return const {};
      if (raw is! List || raw.isEmpty || raw.any((value) => value is! String)) {
        throw const FormatException(
          'daily_slots must contain structured slot strings',
        );
      }
      final parsed = raw.cast<String>().map(DailySlot.fromString).toSet();
      if (parsed.length != raw.length) {
        throw const FormatException('daily_slots must not contain duplicates');
      }
      return parsed;
    }

    final id = requiredString('id');
    final ingredient1 = requiredString('ingredient1');
    final ingredient2 = requiredString('ingredient2');
    final advice = requiredString('advice');
    final ruleType = TimingRuleType.fromString(requiredString('rule_type'));
    final allowedDailySlots = dailySlots();
    final dailyPlanEligibleRaw = json['daily_plan_eligible'];
    if (dailyPlanEligibleRaw != null && dailyPlanEligibleRaw is! bool) {
      throw FormatException('$id: daily_plan_eligible must be a boolean');
    }
    if (ruleType == TimingRuleType.timeOfDay && allowedDailySlots.isEmpty) {
      throw FormatException(
        '$id: time_of_day rule requires reviewed daily_slots',
      );
    }
    if (ruleType != TimingRuleType.timeOfDay && allowedDailySlots.isNotEmpty) {
      throw FormatException(
        '$id: daily_slots are only valid for time_of_day rules',
      );
    }
    final separationRaw = json['separation_hours'];
    if (ruleType == TimingRuleType.separate &&
        (separationRaw is! num || separationRaw <= 0)) {
      throw FormatException(
        '$id: separate timing rule requires positive separation_hours',
      );
    }
    if (json['score_impact'] is! int) {
      throw FormatException('$id: score_impact must be an integer');
    }

    final minDose = json['min_dose'];
    String? minDoseIngredient;
    double? minDoseMg;
    if (minDose is Map) {
      final ing = minDose['ingredient'];
      final mg = minDose['mg'];
      if (ing is String && mg is num) {
        minDoseIngredient = ing.toLowerCase().trim();
        minDoseMg = mg.toDouble();
      }
    }

    return _ParsedTimingRule(
      id: id,
      ingredient1Display: ingredient1,
      ingredient2Display: ingredient2,
      ingredient1Normalized: ingredient1.toLowerCase().trim(),
      ingredient2Normalized: ingredient2.toLowerCase().trim(),
      ruleType: ruleType,
      advice: advice,
      mechanism: json['mechanism'] is String
          ? json['mechanism'] as String
          : null,
      separationHours: separationRaw is num ? separationRaw.toInt() : null,
      scoreImpact: json.safeInt('score_impact'),
      evidenceLevel: EvidenceLevel.fromString(mappedEvidence),
      sourceUrls: sources,
      ingredient1Rxcuis: rxcuis('ingredient1_rxcuis'),
      ingredient2Rxcuis: rxcuis('ingredient2_rxcuis'),
      allowedDailySlots: allowedDailySlots,
      dailyPlanEligible: dailyPlanEligibleRaw as bool? ?? true,
      minDoseIngredient: minDoseIngredient,
      minDoseMg: minDoseMg,
    );
  }

  bool get involvesMedication =>
      ingredient1Rxcuis.isNotEmpty || ingredient2Rxcuis.isNotEmpty;
}

class _IndexedRule {
  final _ParsedTimingRule rule;

  /// True if this rule was indexed via its ingredient1 side.
  /// Used to determine which side is the "other" during matching.
  final bool isIngredient1;

  const _IndexedRule({required this.rule, required this.isIngredient1});
}
