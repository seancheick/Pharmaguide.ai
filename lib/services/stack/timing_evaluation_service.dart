import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';

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
/// Medications are matched via normalized name comparison against a
/// curated medication alias map. When the user adds "Levothyroxine 50mcg",
/// the service normalizes to "levothyroxine" and matches timing rules
/// that reference "levothyroxine" as ingredient1 or ingredient2.
///
/// **Performance:**
///
/// Index build: O(R) where R = number of rules (42 currently).
/// Stack evaluation: O(S × avg_rules_per_ingredient) where S = stack size.
/// For a 50-item stack with 42 rules, this is <1ms on modern devices.
class TimingEvaluationService {
  TimingEvaluationService._({
    required List<_ParsedTimingRule> rules,
    required Map<String, List<_IndexedRule>> ingredientIndex,
    required Map<String, List<_IndexedRule>> medicationIndex,
  })  : _rules = rules,
        _ingredientIndex = ingredientIndex,
        _medicationIndex = medicationIndex;

  /// Number of timing rules loaded.
  int get ruleCount => _rules.length;

  /// All parsed timing rules (internal).
  final List<_ParsedTimingRule> _rules;

  /// ingredient_key → list of rules that reference this ingredient.
  final Map<String, List<_IndexedRule>> _ingredientIndex;

  /// normalized_medication_name → list of rules that reference this medication.
  final Map<String, List<_IndexedRule>> _medicationIndex;

  /// Known medication names that appear in timing rules.
  /// These are matched against the user's medication `name` field.
  static const _medicationKeywords = <String, List<String>>{
    'levothyroxine': [
      'levothyroxine',
      'synthroid',
      'levoxyl',
      'tirosint',
      'euthyrox',
      'l-thyroxine',
    ],
    'warfarin': [
      'warfarin',
      'coumadin',
      'jantoven',
    ],
  };

  /// Supplement ingredient keys that map to timing rule ingredient names.
  /// Most are 1:1 but some need aliases (e.g., timing says "omega-3",
  /// product tags say "omega_3").
  static const _ingredientAliases = <String, List<String>>{
    'iron': ['iron'],
    'calcium': ['calcium'],
    'calcium carbonate': ['calcium_carbonate', 'calcium'],
    'zinc': ['zinc'],
    'copper': ['copper'],
    'magnesium': ['magnesium'],
    'vitamin c': ['vitamin_c'],
    'vitamin d': ['vitamin_d'],
    'vitamin e': ['vitamin_e'],
    'vitamin k': ['vitamin_k'],
    'vitamin b12': ['vitamin_b12'],
    'vitamin b complex': ['vitamin_b1', 'vitamin_b2', 'vitamin_b3', 'vitamin_b5', 'vitamin_b6', 'vitamin_b12'],
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
    final rawRules = json.safeMapList('timing_rules');
    final parsed = <_ParsedTimingRule>[];

    for (final raw in rawRules) {
      parsed.add(_ParsedTimingRule.fromJson(raw));
    }

    // Build inverted indexes.
    final ingredientIndex = <String, List<_IndexedRule>>{};
    final medicationIndex = <String, List<_IndexedRule>>{};

    for (final rule in parsed) {
      final i1Norm = rule.ingredient1Normalized;
      final i2Norm = rule.ingredient2Normalized;

      // Determine which index(es) to populate.
      // If ingredient1 is a medication keyword, index it in medicationIndex.
      final i1IsMed = _isMedicationIngredient(i1Norm);
      final i2IsMed = _isMedicationIngredient(i2Norm);

      // Index ingredient1 side.
      if (i1IsMed) {
        _addToMedIndex(medicationIndex, i1Norm, rule, isIngredient1: true);
      } else {
        _addToIngredientIndex(ingredientIndex, i1Norm, rule,
            isIngredient1: true);
      }

      // Index ingredient2 side (skip non-matchable context like "food",
      // "sleep", "dietary fat", "melatonin production").
      if (!_isContextOnly(i2Norm)) {
        if (i2IsMed) {
          _addToMedIndex(medicationIndex, i2Norm, rule, isIngredient1: false);
        } else {
          _addToIngredientIndex(ingredientIndex, i2Norm, rule,
              isIngredient1: false);
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
  /// [supplementTags] — map of product_name to a Set of canonical ingredient
  ///   tags for each supplement in the stack.
  /// [medicationNames] — list of medication display names in the stack.
  ///
  /// Returns a deduplicated, priority-sorted list of timing advice.
  List<TimingOptimization> evaluateStack({
    required Map<String, Set<String>> supplementTags,
    required List<String> medicationNames,
  }) {
    final results = <String, TimingOptimization>{};

    // Collect all ingredient tags across the entire stack into a
    // tag → [product_names] map for O(1) "is this in the stack?" checks.
    final tagToProducts = <String, List<String>>{};
    for (final entry in supplementTags.entries) {
      for (final tag in entry.value) {
        tagToProducts.putIfAbsent(tag, () => []).add(entry.key);
      }
    }

    // Normalize medication names for matching.
    final normalizedMeds = <String, String>{};
    for (final name in medicationNames) {
      normalizedMeds[_normalize(name)] = name;
    }

    // --- Pass 1: Supplement × Supplement timing rules ---
    // For each tag in the stack, check if any rule references it.
    for (final tag in tagToProducts.keys) {
      final matchingRules = _ingredientIndex[tag];
      if (matchingRules == null) continue;

      for (final indexed in matchingRules) {
        if (results.containsKey(indexed.rule.id)) continue;

        // Find the OTHER side of this rule.
        final otherIngredient = indexed.isIngredient1
            ? indexed.rule.ingredient2Normalized
            : indexed.rule.ingredient1Normalized;

        // Is the other side a context-only value (food, sleep, etc.)?
        // If so, this is a single-ingredient timing rule — always fire.
        if (_isContextOnly(otherIngredient)) {
          final productNames = tagToProducts[tag]!;
          results[indexed.rule.id] = _buildResult(
            indexed.rule,
            product1Name: productNames.first,
            product2Name: null,
          );
          continue;
        }

        // Check if the other ingredient is also in the stack.
        final otherAliases = _resolveAliases(otherIngredient);
        for (final alias in otherAliases) {
          if (tagToProducts.containsKey(alias)) {
            final product1Names = tagToProducts[tag]!;
            final product2Names = tagToProducts[alias]!;
            // Only fire if they're in DIFFERENT products (same product
            // already has them together — that's the formulator's intent).
            final differentProducts = product1Names
                .any((p1) => product2Names.any((p2) => p1 != p2));
            // For single-product stacks with both ingredients, still fire
            // — the advice about timing within the day is still relevant.
            if (differentProducts || product1Names.length == 1) {
              results[indexed.rule.id] = _buildResult(
                indexed.rule,
                product1Name: product1Names.first,
                product2Name: product2Names.first,
              );
            }
            break;
          }
        }
      }
    }

    // --- Pass 2: Medication × Supplement timing rules ---
    for (final entry in normalizedMeds.entries) {
      final normMedName = entry.key;
      final displayMedName = entry.value;

      // Check each medication keyword family.
      for (final kwEntry in _medicationKeywords.entries) {
        final medKey = kwEntry.key;
        final aliases = kwEntry.value;

        if (!aliases.any((a) => normMedName.contains(a))) continue;

        // This medication matches — check if any rule references it.
        final matchingRules = _medicationIndex[medKey];
        if (matchingRules == null) continue;

        for (final indexed in matchingRules) {
          if (results.containsKey(indexed.rule.id)) continue;

          // Find the supplement side of the rule.
          final suppIngredient = indexed.isIngredient1
              ? indexed.rule.ingredient2Normalized
              : indexed.rule.ingredient1Normalized;

          if (_isContextOnly(suppIngredient)) {
            // Medication-only rule (e.g., "take levothyroxine on empty
            // stomach") — always fire if the medication is in the stack.
            results[indexed.rule.id] = _buildResult(
              indexed.rule,
              product1Name: displayMedName,
              product2Name: null,
            );
            continue;
          }

          // Check if the supplement side is in the stack.
          final suppAliases = _resolveAliases(suppIngredient);
          for (final alias in suppAliases) {
            if (tagToProducts.containsKey(alias)) {
              final suppProducts = tagToProducts[alias]!;
              results[indexed.rule.id] = _buildResult(
                indexed.rule,
                product1Name: displayMedName,
                product2Name: suppProducts.first,
              );
              break;
            }
          }
        }
      }
    }

    // Sort by priority (medication interactions first, then separations,
    // then other types).
    final sorted = results.values.toList()
      ..sort((a, b) => b.displayPriority.compareTo(a.displayPriority));

    return sorted;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  TimingOptimization _buildResult(
    _ParsedTimingRule rule, {
    String? product1Name,
    String? product2Name,
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
      product1Name: product1Name,
      product2Name: product2Name,
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

  static bool _isMedicationIngredient(String normalized) {
    return _medicationKeywords.containsKey(normalized);
  }

  /// Context-only ingredients that don't correspond to a real stack item.
  /// These are the "other side" of single-ingredient timing rules like
  /// "take CoQ10 with food" where ingredient2 = "dietary fat".
  static bool _isContextOnly(String normalized) {
    const contextTerms = {
      'food',
      'dietary fat',
      'sleep',
      'melatonin',
      'melatonin production',
      'minerals',
    };
    return contextTerms.contains(normalized);
  }

  static String _normalize(String text) {
    return text.toLowerCase().trim();
  }

  static void _addToIngredientIndex(
    Map<String, List<_IndexedRule>> index,
    String ingredientName,
    _ParsedTimingRule rule, {
    required bool isIngredient1,
  }) {
    final aliases = _ingredientAliases[ingredientName];
    final keys = aliases ?? [ingredientName.replaceAll(' ', '_').replaceAll('-', '_')];
    for (final key in keys) {
      index
          .putIfAbsent(key, () => [])
          .add(_IndexedRule(rule: rule, isIngredient1: isIngredient1));
    }
  }

  static void _addToMedIndex(
    Map<String, List<_IndexedRule>> index,
    String medicationName,
    _ParsedTimingRule rule, {
    required bool isIngredient1,
  }) {
    index
        .putIfAbsent(medicationName, () => [])
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
  });

  factory _ParsedTimingRule.fromJson(Map<String, dynamic> json) {
    final sources = json
        .safeMapList('sources')
        .map((s) => s.safeString('url'))
        .where((url) => url.isNotEmpty)
        .toList(growable: false);

    final evidenceStr = json.safeString('evidence_level', 'possible');
    // Map "possible" → "theoretical" since EvidenceLevel enum doesn't have "possible"
    final mappedEvidence =
        evidenceStr == 'possible' ? 'theoretical' : evidenceStr;

    final ingredient1 = json.safeString('ingredient1');
    final ingredient2 = json.safeString('ingredient2');
    final separationRaw = json['separation_hours'];

    return _ParsedTimingRule(
      id: json.safeString('id'),
      ingredient1Display: ingredient1,
      ingredient2Display: ingredient2,
      ingredient1Normalized: ingredient1.toLowerCase().trim(),
      ingredient2Normalized: ingredient2.toLowerCase().trim(),
      ruleType: TimingRuleType.fromString(
          json.safeString('rule_type', 'separate')),
      advice: json.safeString('advice'),
      mechanism: json['mechanism'] is String
          ? json['mechanism'] as String
          : null,
      separationHours: separationRaw is num ? separationRaw.toInt() : null,
      scoreImpact: json.safeInt('score_impact'),
      evidenceLevel: EvidenceLevel.fromString(mappedEvidence),
      sourceUrls: sources,
    );
  }
}

class _IndexedRule {
  final _ParsedTimingRule rule;

  /// True if this rule was indexed via its ingredient1 side.
  /// Used to determine which side is the "other" during matching.
  final bool isIngredient1;

  const _IndexedRule({required this.rule, required this.isIngredient1});
}
