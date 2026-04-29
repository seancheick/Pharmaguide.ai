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
// NOTE — Pre-existing bug in [E1DosageCalculator]: it reads
// `entry['nutrient']` and `group['age_bracket']` / `group['rda']`,
// which do not exist in the real data file (the actual fields are
// `standard_name`, `age_range`, `rda_ai`). This means the legacy
// calculator always falls through to `highest_ul` and never applies
// RDA tier scoring. This checker deliberately reads the correct
// field names. Out of scope for M1 to fix the legacy path — file an
// issue instead.

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
    final entry = _findEntry(recommendations, total);
    if (entry == null) {
      return NutrientStatus(total: total, tier: NutrientTier.noRda);
    }

    final rdaLookup = _getRdaWithProvenance(
      entry,
      ageBracket: ageBracket,
      sex: sex,
    );
    final rda = rdaLookup.value;
    final ul = _getUl(entry, ageBracket: ageBracket, sex: sex);

    final pctOfRda = (rda != null && rda > 0)
        ? (total.totalAmount / rda) * 100.0
        : null;
    final pctOfUl = (ul != null && ul > 0)
        ? (total.totalAmount / ul) * 100.0
        : null;

    final tier = _classify(pctOfRda: pctOfRda, pctOfUl: pctOfUl);
    final warning =
        (tier == NutrientTier.approachingUl || tier == NutrientTier.exceedsUl)
        ? _warningFor(total.canonicalId, tier)
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
    );
  }

  /// Find the best matching nutrient entry. Four-tier lookup:
  /// 1. Exact id match
  /// 2. Exact lowercased standard_name match against display name
  /// 3. Substring match against display name
  /// 4. null
  Map<String, dynamic>? _findEntry(
    List<dynamic> recommendations,
    NutrientTotal total,
  ) {
    final canonical = total.canonicalId.toLowerCase();
    final display = total.displayName.toLowerCase();

    // Tier 1: exact id match.
    for (final e in recommendations) {
      if (e is! Map<String, dynamic>) continue;
      final id = (e['id'] ?? '').toString().toLowerCase();
      if (id.isNotEmpty && id == canonical) return e;
    }

    // Tier 2: exact standard_name match (lowercased) against our
    // display name. This catches cases where the aggregator produced
    // a canonical id that isn't in rda_optimal_uls (e.g. "epa" not
    // tracked there) but the human name matches.
    for (final e in recommendations) {
      if (e is! Map<String, dynamic>) continue;
      final std = (e['standard_name'] ?? '').toString().toLowerCase();
      if (std.isNotEmpty && std == display) return e;
    }

    // Tier 3: substring fuzzy match. Deliberately last because it
    // can mis-match (e.g. "vitamin a" is a substring of "vitamin a
    // palmitate"). Only used when no exact match exists.
    for (final e in recommendations) {
      if (e is! Map<String, dynamic>) continue;
      final std = (e['standard_name'] ?? '').toString().toLowerCase();
      if (std.isEmpty) continue;
      if (display.contains(std) || std.contains(display)) return e;
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

  /// Look up UL for the requested demographic. Falls back to
  /// `highest_ul` for anonymous users so the critical
  /// "exceeds UL" warning still fires without a profile.
  double? _getUl(
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
          if (v != null) return v;
        }
      }
    }

    if (ageBracket != null) {
      for (final g in data) {
        if (g is! Map<String, dynamic>) continue;
        if (g['age_range'] == ageBracket) {
          final v = _asDouble(g['ul']);
          if (v != null) return v;
        }
      }
    }

    // Anonymous fallback: highest_ul lets us still catch UL breaches
    // without a profile. This is the most conservative number so it
    // errs on the side of safety.
    final highest = _asDouble(entry['highest_ul']);
    if (highest != null) return highest;

    return null;
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
    if (pctOfRda > 200.0) return NutrientTier.aboveTypical;
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
          ? specific
          : 'Approaching Upper Limit — $specific'.toLowerCase().replaceFirst(
              'approaching upper limit — ',
              'Approaching Upper Limit — ',
            );
    }
    return tier == NutrientTier.exceedsUl
        ? 'Exceeds Upper Limit — review with healthcare provider'
        : 'Approaching Upper Limit — consider reducing dose';
  }

  static const Map<String, String> _specificWarnings = {
    'zinc': 'Exceeds Upper Limit — risk of copper depletion',
    'iron': 'Exceeds Upper Limit — risk of GI toxicity and oxidative stress',
    'vitamin_a':
        'Exceeds Upper Limit — risk of hepatotoxicity and teratogenicity',
    'vitamin_d':
        'Exceeds Upper Limit — risk of hypercalcemia and kidney damage',
    'vitamin_d3':
        'Exceeds Upper Limit — risk of hypercalcemia and kidney damage',
    'vitamin_b6':
        'Exceeds Upper Limit — risk of sensory neuropathy with chronic use',
    'vitamin_b3': 'Exceeds Upper Limit — risk of flushing and hepatotoxicity',
    'niacin': 'Exceeds Upper Limit — risk of flushing and hepatotoxicity',
    'folate': 'Exceeds Upper Limit — may mask vitamin B12 deficiency',
    'folic_acid': 'Exceeds Upper Limit — may mask vitamin B12 deficiency',
    'calcium':
        'Exceeds Upper Limit — risk of kidney stones and cardiovascular events',
    'magnesium':
        'Exceeds Upper Limit — risk of diarrhea and electrolyte imbalance',
    'selenium': 'Exceeds Upper Limit — risk of selenosis and hair/nail loss',
    'copper': 'Exceeds Upper Limit — risk of hepatotoxicity',
    'manganese':
        'Exceeds Upper Limit — risk of neurotoxicity with chronic exposure',
    'iodine': 'Exceeds Upper Limit — risk of thyroid dysfunction',
  };

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
