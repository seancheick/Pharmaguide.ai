// StackUlChecker — classifies aggregated stack nutrient totals
// against RDA and UL benchmarks from `rda_optimal_uls.json`. Used
// by the M1 stack nutrient accumulation panel.
//
// INPUT
//
// * [rdaData] — the full decoded JSON from
//   `assets/reference_data/rda_optimal_uls.json`, loaded via
//   [ReferenceDataRepository]. Keyed shape:
//     {
//       "_metadata": {...},
//       "nutrient_recommendations": [
//         {
//           "id": "vitamin_a",
//           "standard_name": "Vitamin A",
//           "highest_ul": 3000,
//           "data": [
//             {
//               "group": "Male",
//               "age_range": "19-30",
//               "rda_ai": 900,
//               "ul": 3000
//             },
//             ...
//           ]
//         }
//       ]
//     }
//
// * Aggregated stack totals from [StackNutrientAggregator.aggregate].
//
// OUTPUT
//
// A [NutrientStatus] for every aggregated nutrient. Status carries
// the tier classification, the numeric %RDA and %UL, and a
// human-readable warning string when the tier is approaching or
// exceeding the UL.
//
// LOOKUP STRATEGY
//
// 1. Exact match on `id` (canonical lowercase, e.g. "vitamin_a").
//    This is the fast path because our aggregator produces canonical
//    ids that match the pipeline convention.
// 2. Exact match on `standard_name` (lowercased).
// 3. Substring fallback on `standard_name`.
// 4. Nothing found → [NutrientTier.noRda].
//
// AGE / SEX LOOKUP
//
// `rda_optimal_uls.json` stores per-demographic rows. We look up in
// priority order:
// 1. Exact age_range AND group (sex) match.
// 2. Any row with the requested age_range (regardless of sex).
// 3. `entry.highest_ul` as a last-resort UL for anonymous users.
//
// RDA and UL are read separately — a nutrient can have a UL
// without an RDA (and vice versa), so we never assume both exist.
//
// FitScore E1/E2b route through this same checker so the product-detail
// score and stack nutrient panel use the same nutrient identity, unit, and
// demographic rules.

import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

class StackUlChecker {
  const StackUlChecker({required this.rdaData});

  final Map<String, dynamic> rdaData;

  /// Classify every aggregated nutrient against RDA/UL benchmarks.
  ///
  /// [ageBracket] is a string like "19-30" matching the age_range
  /// values in the reference data. [sex] is "Male" / "Female" /
  /// "Pregnancy" / "Lactation" matching the group field.
  ///
  /// Both are optional — when null, the checker still runs with the
  /// `highest_ul` fallback, which gives anonymous users a usable
  /// safety check even without a profile.
  List<NutrientStatus> check(
    Map<String, NutrientTotal> aggregated, {
    String? ageBracket,
    String? sex,
  }) {
    final recommendations =
        (rdaData['nutrient_recommendations'] as List?) ?? const [];

    final results = <NutrientStatus>[];
    for (final total in aggregated.values) {
      results.add(
        _classifyOne(total, recommendations, ageBracket: ageBracket, sex: sex),
      );
    }
    return results;
  }

  NutrientStatus _classifyOne(
    NutrientTotal total,
    List<dynamic> recommendations, {
    required String? ageBracket,
    required String? sex,
  }) {
    final resolved = _findEntry(recommendations, total);
    if (resolved == null) {
      return NutrientStatus(total: total, tier: NutrientTier.noRda);
    }
    final entry = resolved.entry;

    final amountInReferenceUnit = _amountInReferenceUnit(
      total.totalAmount,
      actualUnit: total.unit,
      expectedUnit: (entry['unit'] ?? '').toString(),
    );
    if (amountInReferenceUnit == null) {
      return NutrientStatus(total: total, tier: NutrientTier.noRda);
    }

    final rdaLookup = _getRdaWithProvenance(
      entry,
      ageBracket: ageBracket,
      sex: sex,
    );
    final rda = rdaLookup.value;
    final ulLookup = _getUlWithProvenance(
      entry,
      ageBracket: ageBracket,
      sex: sex,
    );
    final ul = ulLookup.value;

    final pctOfRda = (rda != null && rda > 0)
        ? (amountInReferenceUnit / rda) * 100.0
        : null;
    final pctOfUl = (ul != null && ul > 0)
        ? (amountInReferenceUnit / ul) * 100.0
        : null;

    final tier = _classify(pctOfRda: pctOfRda, pctOfUl: pctOfUl);
    final warning =
        (tier == NutrientTier.approachingUl || tier == NutrientTier.exceedsUl)
        ? _warningFor(resolved.id, tier)
        : null;

    return NutrientStatus(
      total: total,
      tier: tier,
      rda: rda,
      ul: ul,
      pctOfRda: pctOfRda,
      pctOfUl: pctOfUl,
      warning: warning,
      rdaIsBaseline: rdaLookup.isBaseline,
      ulIsFallback: ulLookup.isFallback,
    );
  }

  /// Find the best matching nutrient entry. Four-tier lookup:
  /// 1. Exact id match
  /// 2. Exact lowercased standard_name match against display name
  /// 3. Substring match against display name
  /// 4. null
  _ResolvedEntry? _findEntry(
    List<dynamic> recommendations,
    NutrientTotal total,
  ) {
    final canonical = _normalizeKey(total.canonicalId);
    final display = total.displayName.toLowerCase();
    final aliased = _rdaAliases[canonical];

    // Tier 1: exact id match, with explicit pipeline-id aliases.
    for (final e in recommendations) {
      if (e is! Map<String, dynamic>) continue;
      final id = _normalizeKey(e['id']);
      if (id.isEmpty) continue;
      if (id == canonical || id == aliased) {
        return _ResolvedEntry(entry: e, id: id);
      }
    }

    // Tier 2: exact standard_name match (lowercased) against our
    // display name. This catches cases where the aggregator produced
    // a canonical id that isn't in rda_optimal_uls (e.g. "epa" not
    // tracked there) but the human name matches.
    for (final e in recommendations) {
      if (e is! Map<String, dynamic>) continue;
      final std = (e['standard_name'] ?? '').toString().toLowerCase();
      if (std.isNotEmpty && std == display) {
        return _ResolvedEntry(entry: e, id: _normalizeKey(e['id']));
      }
    }

    // Tier 3: substring fuzzy match. Deliberately last because it
    // can mis-match (e.g. "vitamin a" is a substring of "vitamin a
    // palmitate"). Only used when no exact match exists, and only
    // for meaningful word-boundary strings.
    for (final e in recommendations) {
      if (e is! Map<String, dynamic>) continue;
      final std = (e['standard_name'] ?? '').toString().toLowerCase();
      if (std.isEmpty) continue;
      if (_safeWordContains(display, std) || _safeWordContains(std, display)) {
        return _ResolvedEntry(entry: e, id: _normalizeKey(e['id']));
      }
    }

    return null;
  }

  /// RDA lookup result paired with provenance. [isBaseline] is true
  /// when the value came from the anonymous adult fallback.
  _RdaLookup _getRdaWithProvenance(
    Map<String, dynamic> entry, {
    required String? ageBracket,
    required String? sex,
  }) {
    final data = (entry['data'] as List?) ?? const [];
    if (data.isEmpty) return const _RdaLookup(null, false);

    // Tier 1: exact age + sex match.
    if (ageBracket != null && sex != null) {
      for (final g in data) {
        if (g is! Map<String, dynamic>) continue;
        if (g['age_range'] == ageBracket && g['group'] == sex) {
          final v = _asDouble(g['rda_ai'] ?? g['rda'] ?? g['ai']);
          if (v != null) return _RdaLookup(v, false);
        }
      }
    }

    // Tier 2: age match with any group (first seen).
    if (ageBracket != null) {
      for (final g in data) {
        if (g is! Map<String, dynamic>) continue;
        if (g['age_range'] == ageBracket) {
          final v = _asDouble(g['rda_ai'] ?? g['rda'] ?? g['ai']);
          if (v != null) return _RdaLookup(v, false);
        }
      }
    }

    // Tier 3: anonymous baseline — adult 19-30 Female. Matches the
    // FDA supplement-facts Daily Value convention (non-pregnant,
    // non-lactating adult) and is the conservative direction — Female
    // RDA is ≤ Male for most nutrients, so %RDA won't be
    // under-reported for anonymous users. Flagged as baseline so the
    // UI can show a "set your profile for personalized values" hint.
    for (final g in data) {
      if (g is! Map<String, dynamic>) continue;
      if (g['age_range'] == '19-30' && g['group'] == 'Female') {
        final v = _asDouble(g['rda_ai'] ?? g['rda'] ?? g['ai']);
        if (v != null) return _RdaLookup(v, true);
      }
    }

    return const _RdaLookup(null, false);
  }

  /// Look up UL for the requested demographic. Falls back to `highest_ul`
  /// for anonymous users. This is the least restrictive demographic UL, not
  /// the most conservative one; callers receive provenance so UI can ask for
  /// a profile when values are not personalized.
  _UlLookup _getUlWithProvenance(
    Map<String, dynamic> entry, {
    required String? ageBracket,
    required String? sex,
  }) {
    final data = (entry['data'] as List?) ?? const [];

    if (ageBracket != null && sex != null) {
      for (final g in data) {
        if (g is! Map<String, dynamic>) continue;
        if (g['age_range'] == ageBracket && g['group'] == sex) {
          final v = _asDouble(g['ul']);
          if (v != null) return _UlLookup(v, false);
        }
      }
    }

    if (ageBracket != null) {
      for (final g in data) {
        if (g is! Map<String, dynamic>) continue;
        if (g['age_range'] == ageBracket) {
          final v = _asDouble(g['ul']);
          if (v != null) return _UlLookup(v, false);
        }
      }
    }

    // Anonymous fallback: least restrictive UL lets us still catch large
    // overages without alarming users from an unknown demographic.
    final highest = _asDouble(entry['highest_ul']);
    if (highest != null) return _UlLookup(highest, true);

    return const _UlLookup(null, false);
  }

  /// Classify into a [NutrientTier]. UL precedence is strict —
  /// exceedsUl and approachingUl always override RDA tiers because
  /// the UL story is more important to the user than the RDA story.
  NutrientTier _classify({
    required double? pctOfRda,
    required double? pctOfUl,
  }) {
    if (pctOfUl != null) {
      if (pctOfUl >= 100.0) return NutrientTier.exceedsUl;
      if (pctOfUl >= 80.0) return NutrientTier.approachingUl;
    }
    if (pctOfRda == null) return NutrientTier.noRda;
    if (pctOfRda >= 200.0) return NutrientTier.aboveTypical;
    if (pctOfRda >= 100.0) return NutrientTier.abundant;
    if (pctOfRda >= 50.0) return NutrientTier.adequate;
    return NutrientTier.underFifty;
  }

  /// Nutrient-specific warning strings. These map to known toxicity
  /// pathways and are shown verbatim in the UI. Extend carefully —
  /// each message here has medical implications.
  String _warningFor(String canonicalId, NutrientTier tier) {
    final key = canonicalId.toLowerCase();
    final specific = _specificWarnings[key];
    if (specific != null) {
      return tier == NutrientTier.exceedsUl
          ? 'Exceeds Upper Limit — $specific'
          : 'Approaching Upper Limit — $specific';
    }
    return tier == NutrientTier.exceedsUl
        ? 'Exceeds Upper Limit — review with healthcare provider'
        : 'Approaching Upper Limit — consider reducing dose';
  }

  static const Map<String, String> _specificWarnings = {
    'zinc': 'risk of copper depletion',
    'iron': 'risk of GI toxicity and oxidative stress',
    'vitamin_a': 'risk of hepatotoxicity and teratogenicity',
    'vitamin_d': 'risk of hypercalcemia and kidney damage',
    'vitamin_d3': 'risk of hypercalcemia and kidney damage',
    'vitamin_b6': 'risk of sensory neuropathy with chronic use',
    'vitamin_b3': 'risk of flushing and hepatotoxicity',
    'niacin': 'risk of flushing and hepatotoxicity',
    'folate': 'may mask vitamin B12 deficiency',
    'folic_acid': 'may mask vitamin B12 deficiency',
    'calcium': 'risk of kidney stones and cardiovascular events',
    'magnesium': 'risk of diarrhea and electrolyte imbalance',
    'selenium': 'risk of selenosis and hair/nail loss',
    'copper': 'risk of hepatotoxicity',
    'manganese': 'risk of neurotoxicity with chronic exposure',
    'iodine': 'risk of thyroid dysfunction',
  };

  static const Map<String, String> _rdaAliases = {
    'vitamin_b1_thiamine': 'thiamin',
    'vitamin_b2_riboflavin': 'riboflavin',
    'vitamin_b3_niacin': 'niacin',
    'vitamin_b5_pantothenic_acid': 'pantothenic_acid',
    'vitamin_b6_pyridoxine': 'vitamin_b6',
    'vitamin_b7_biotin': 'biotin',
    'vitamin_b9_folate': 'folate',
    'vitamin_b12_cobalamin': 'vitamin_b12',
    'vitamin_d2': 'vitamin_d',
    'vitamin_d3': 'vitamin_d',
  };

  static double? _amountInReferenceUnit(
    double amount, {
    required String actualUnit,
    required String expectedUnit,
  }) {
    if (_unitMatchesReference(actualUnit, expectedUnit)) return amount;

    final expected = _normalizeUnit(expectedUnit);
    final actual = _normalizeUnit(actualUnit);
    final actualGrams = _simpleMassGramsFactor(actual);
    final expectedGrams = _simpleMassGramsFactor(expected);
    if (actualGrams == null || expectedGrams == null) return null;
    return amount * actualGrams / expectedGrams;
  }

  static bool _unitMatchesReference(String actual, String expected) {
    final expectedUnit = _normalizeUnit(expected);
    if (expectedUnit.isEmpty) return true;
    final actualUnit = _normalizeUnit(actual);
    if (actualUnit.isEmpty) return false;
    if (actualUnit == expectedUnit) return true;

    const aliases = <String, Set<String>>{
      'mcg': {'ug'},
      'mcg rae': {'ug rae'},
      'mcg dfe': {'ug dfe'},
      'mg alpha tocopherol': {'mg alpha-tocopherol', 'mg'},
      'mg ne': {'mg'},
    };
    return aliases[expectedUnit]?.contains(actualUnit) ?? false;
  }

  static double? _simpleMassGramsFactor(String unit) {
    return switch (unit) {
      'g' => 1.0,
      'gram' => 1.0,
      'grams' => 1.0,
      'gram(s)' => 1.0,
      'mg' => 0.001,
      'mcg' => 0.000001,
      'microgram' => 0.000001,
      'micrograms' => 0.000001,
      _ => null,
    };
  }

  static String _normalizeKey(Object? raw) {
    return (raw ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  static String _normalizeUnit(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll('µg', 'mcg')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _safeWordContains(String haystack, String needle) {
    if (haystack.length < 4 || needle.length < 4) return false;
    final escaped = RegExp.escape(needle);
    return RegExp('(^|[^a-z0-9])$escaped([^a-z0-9]|\$)').hasMatch(haystack);
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v.isFinite ? v : null;
    if (v is int) return v.toDouble();
    if (v is String) {
      final parsed = double.tryParse(v.trim());
      return (parsed != null && parsed.isFinite) ? parsed : null;
    }
    return null;
  }
}

/// RDA lookup result paired with whether the value came from the
/// anonymous baseline fallback. Internal-only — the checker unwraps
/// it before returning a [NutrientStatus].
class _RdaLookup {
  const _RdaLookup(this.value, this.isBaseline);
  final double? value;
  final bool isBaseline;
}

class _UlLookup {
  const _UlLookup(this.value, this.isFallback);
  final double? value;
  final bool isFallback;
}

class _ResolvedEntry {
  const _ResolvedEntry({required this.entry, required this.id});
  final Map<String, dynamic> entry;
  final String id;
}
