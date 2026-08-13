// StackUlChecker — classifies aggregated stack nutrient totals
// against intake-target and UL benchmarks from `rda_optimal_uls.json`. Used
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
// the tier classification, the numeric % target and %UL, and a
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
// 3. Lowest established demographic UL as a conservative anonymous fallback.
//
// RDA and UL are read separately — a nutrient can have a UL
// without an RDA (and vice versa), so we never assume both exist.
//
// FitScore E1/E2b route through this same checker so the product-detail
// score and stack nutrient panel use the same nutrient identity, unit, and
// demographic rules.

import 'package:pharmaguide/core/units/dose_units.dart';
import 'package:pharmaguide/core/utils/num_parse.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
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
  /// Both are optional — when null, the checker still runs against the lowest
  /// established demographic UL. The result is marked as a fallback so the UI
  /// can explain that completing the profile improves personalization.
  /// [pipelineVerdicts] carries the pipeline's own per-nutrient UL decisions
  /// (keyed by canonical id, from
  /// [StackNutrientAggregator.extractPipelineUlVerdicts]). When a definitive
  /// verdict exists for a nutrient it is PREFERRED over the client's recompute
  /// — the pipeline resolves elemental-vs-compound mass and form-aware unit
  /// conversions the client cannot reconstruct from raw quantities. Absent by
  /// default, so callers that don't supply verdicts keep the pure recompute.
  List<NutrientStatus> check(
    Map<String, NutrientTotal> aggregated, {
    String? ageBracket,
    String? sex,
    Map<String, PipelineUlVerdict> pipelineVerdicts = const {},
  }) {
    final recommendations =
        (rdaData['nutrient_recommendations'] as List?) ?? const [];

    final results = <NutrientStatus>[];
    for (final total in aggregated.values) {
      results.add(
        _classifyOne(
          total,
          recommendations,
          ageBracket: ageBracket,
          sex: sex,
          verdict: pipelineVerdicts[total.canonicalId],
        ),
      );
    }
    return results;
  }

  NutrientStatus _classifyOne(
    NutrientTotal total,
    List<dynamic> recommendations, {
    required String? ageBracket,
    required String? sex,
    PipelineUlVerdict? verdict,
  }) {
    final resolved = _findEntry(recommendations, total);
    if (resolved == null) {
      return NutrientStatus(total: total, tier: NutrientTier.noRda);
    }
    final entry = resolved.entry;

    final expectedUnit = (entry['unit'] ?? '').toString();
    final adequacyAmountInReferenceUnit = _adequacyAmountInReferenceUnit(
      total.adequacyAmount,
      nutrientId: resolved.id,
      actualUnit: total.unit,
      expectedUnit: expectedUnit,
    );
    final maximumAdequacyAmountInReferenceUnit = _adequacyAmountInReferenceUnit(
      total.totalAmount,
      nutrientId: resolved.id,
      actualUnit: total.unit,
      expectedUnit: expectedUnit,
    );
    final safetyAmount = total.hasUlExposureContract
        ? total.ulComparableTotalAmount
        : total.totalAmount;
    final safetyUnit = total.hasUlExposureContract
        ? (total.ulComparableUnit ?? '')
        : total.unit;
    final safetyAmountInReferenceUnit = safetyAmount == null
        ? null
        : _amountInReferenceUnit(
            safetyAmount,
            actualUnit: safetyUnit,
            expectedUnit: expectedUnit,
          );
    if (adequacyAmountInReferenceUnit == null &&
        safetyAmountInReferenceUnit == null) {
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

    final pctOfRda =
        (rda != null && rda > 0 && adequacyAmountInReferenceUnit != null)
        ? (adequacyAmountInReferenceUnit / rda) * 100.0
        : null;
    final maximumPctOfRda =
        (rda != null && rda > 0 && maximumAdequacyAmountInReferenceUnit != null)
        ? (maximumAdequacyAmountInReferenceUnit / rda) * 100.0
        : null;
    final recomputedPctOfUl =
        (ul != null && ul > 0 && safetyAmountInReferenceUnit != null)
        ? (safetyAmountInReferenceUnit / ul) * 100.0
        : null;
    // A positive pipeline decision may carry form-aware information the raw
    // client row cannot reconstruct, so it wins. A negative per-product
    // decision cannot clear an aggregated stack total: two individually safe
    // products can exceed the UL together. In that case the stack recompute
    // wins and the displayed percentage stays aligned with the tier.
    final pctOfUl =
        (verdict?.overUl == true ||
            (verdict?.overUl == null && verdict?.pctUl != null))
        ? (verdict?.pctUl ?? recomputedPctOfUl)
        : (recomputedPctOfUl ?? verdict?.pctUl);

    final tier = _classify(
      pctOfRda: pctOfRda,
      pctOfUl: pctOfUl,
      hasEstablishedUl: ul != null,
      verdict: verdict,
    );
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
      maximumPctOfRda: maximumPctOfRda,
      pctOfUl: pctOfUl,
      warning: warning,
      rdaIsBaseline: rdaLookup.isBaseline,
      ulIsFallback: ulLookup.isFallback,
      ulAssessmentIndeterminate:
          ul != null &&
          (total.hasUnresolvedUlContribution ||
              (!total.hasUlExposureContract &&
                  safetyAmountInReferenceUnit == null)) &&
          (verdict == null || !verdict.isDefinitive),
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
          final v = asFiniteDouble(g['rda_ai'] ?? g['rda'] ?? g['ai']);
          if (v != null) return _RdaLookup(v, false);
        }
      }
    }

    // Tier 2: age matches but sex didn't (null, 'Other', 'Prefer not
    // to say', or no row for that group). Prefer the Female row at the
    // same age — the conservative direction for most nutrients (Female
    // RDA <= Male), consistent with the tier-3 rationale — and FLAG it
    // as baseline: the value is age-personalized but not
    // sex-personalized, so the UI's "set your profile" hint applies.
    // Never silently hand an unspecified-sex user the Male target
    // (wrong direction on e.g. iron: Male 8 vs Female 18).
    if (ageBracket != null) {
      for (final g in data) {
        if (g is! Map<String, dynamic>) continue;
        if (g['age_range'] == ageBracket && g['group'] == 'Female') {
          final v = asFiniteDouble(g['rda_ai'] ?? g['rda'] ?? g['ai']);
          if (v != null) return _RdaLookup(v, true);
        }
      }
      for (final g in data) {
        if (g is! Map<String, dynamic>) continue;
        if (g['age_range'] == ageBracket) {
          final v = asFiniteDouble(g['rda_ai'] ?? g['rda'] ?? g['ai']);
          if (v != null) return _RdaLookup(v, true);
        }
      }
    }

    // Tier 3: anonymous baseline — adult 19-30 Female. Matches the
    // FDA supplement-facts Daily Value convention (non-pregnant,
    // non-lactating adult) and is the conservative direction — Female
    // RDA is <= Male for most nutrients, so target coverage won't be
    // under-reported for anonymous users. Flagged as baseline so the
    // UI can show a "set your profile for personalized values" hint.
    for (final g in data) {
      if (g is! Map<String, dynamic>) continue;
      if (g['age_range'] == '19-30' && g['group'] == 'Female') {
        final v = asFiniteDouble(g['rda_ai'] ?? g['rda'] ?? g['ai']);
        if (v != null) return _RdaLookup(v, true);
      }
    }

    return const _RdaLookup(null, false);
  }

  /// Look up UL for the requested demographic. Anonymous users receive the
  /// lowest established ceiling in the bundled demographic table. That is the
  /// safe direction when age/sex are unknown; callers receive provenance so
  /// UI can ask for a profile rather than pretending the value is personal.
  _UlLookup _getUlWithProvenance(
    Map<String, dynamic> entry, {
    required String? ageBracket,
    required String? sex,
  }) {
    // Floor nutrients have no official UL (vitamin K, B12, biotin, and
    // nutrients like vanadium whose only `highest_ul` is a soft toxicity-study
    // estimate). The data's `nutrient_class` is authoritative — gate here so a
    // soft `highest_ul` can never leak a false ceiling into the tiering and
    // push a benign nutrient into amber/red. Dual-read: when the field is
    // absent (older bundled data) we fall through to the legacy UL inference.
    if ((entry['nutrient_class'] ?? '').toString() == 'floor') {
      return const _UlLookup(null, false);
    }

    final data = (entry['data'] as List?) ?? const [];

    if (ageBracket != null && sex != null) {
      for (final g in data) {
        if (g is! Map<String, dynamic>) continue;
        if (g['age_range'] == ageBracket && g['group'] == sex) {
          final v = asFiniteDouble(g['ul']);
          if (v != null) return _UlLookup(v, false);
        }
      }
    }

    // Age matches but sex didn't: take the LOWEST UL across groups at
    // that age (conservative — never under-warn an unspecified-sex
    // user), flagged as non-personalized.
    if (ageBracket != null) {
      double? lowest;
      for (final g in data) {
        if (g is! Map<String, dynamic>) continue;
        if (g['age_range'] == ageBracket) {
          final v = asFiniteDouble(g['ul']);
          if (v != null && (lowest == null || v < lowest)) lowest = v;
        }
      }
      if (lowest != null) return _UlLookup(lowest, true);
    }

    // Anonymous fallback: choose the lowest established ceiling. `highest_ul`
    // previously selected the least restrictive group and silently
    // under-warned adolescents and other unmatched profiles.
    double? lowest;
    for (final g in data) {
      if (g is! Map<String, dynamic>) continue;
      final v = asFiniteDouble(g['ul']);
      if (v != null && (lowest == null || v < lowest)) lowest = v;
    }
    if (lowest != null) return _UlLookup(lowest, true);

    return const _UlLookup(null, false);
  }

  /// Classify into a [NutrientTier]. UL precedence is strict —
  /// exceedsUl and approachingUl always override RDA tiers because
  /// the UL story is more important to the user than the RDA story.
  NutrientTier _classify({
    required double? pctOfRda,
    required double? pctOfUl,
    required bool hasEstablishedUl,
    PipelineUlVerdict? verdict,
  }) {
    // The pipeline's UL verdict takes precedence over the client recompute:
    // it accounts for elemental-vs-compound mass and form-aware conversions
    // that raw quantity ÷ reference cannot. Only recompute when no definitive
    // verdict exists.
    if (verdict?.overUl == true) return NutrientTier.exceedsUl;
    if (pctOfUl != null) {
      if (pctOfUl >= 100.0) return NutrientTier.exceedsUl;
      if (pctOfUl >= 80.0) return NutrientTier.approachingUl;
    }
    if (pctOfRda == null) return NutrientTier.noRda;
    // No UL exists for this nutrient (vitamin K, B12, biotin, omega-3,
    // CoQ10, potassium, ...). High intake is benign — there is no ceiling to
    // approach — so it must NEVER escalate to the amber abundant/aboveTypical
    // tiers (those imply a UL to monitor toward). Anything at or above the
    // intake target is a calm "above adequate".
    if (!hasEstablishedUl) {
      if (pctOfRda >= 100.0) return NutrientTier.aboveAdequateNoUl;
      if (pctOfRda >= 50.0) return NutrientTier.adequate;
      return NutrientTier.underFifty;
    }
    // UL-bounded nutrient, currently below 80% of its UL — classify by target.
    if (pctOfRda >= 200.0) return NutrientTier.aboveTypical;
    if (pctOfRda >= 100.0) return NutrientTier.abundant;
    if (pctOfRda >= 50.0) return NutrientTier.adequate;
    return NutrientTier.underFifty;
  }

  /// Nutrient-specific warning strings. These map to known toxicity
  /// pathways and are shown verbatim in the UI. Extend carefully —
  /// each message here has medical implications.
  String? _warningFor(String canonicalId, NutrientTier tier) {
    final key = canonicalId.toLowerCase();
    final warnings = rdaData['consumer_ul_warnings'];
    if (warnings is! Map) return null;
    final record = warnings[key] ?? warnings[_rdaAliases[key]];
    if (record is! Map) return null;
    final specific = record['message']?.toString().trim();
    if (specific == null || specific.isEmpty) return null;
    return tier == NutrientTier.exceedsUl
        ? 'Above the upper limit — $specific'
        : 'Approaching the upper limit — $specific';
  }

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

    final expected = normalizeDoseUnit(expectedUnit);
    final actual = normalizeDoseUnit(actualUnit);
    final actualGrams = massGramsFactor(actual);
    final expectedGrams = massGramsFactor(expected);
    if (actualGrams == null || expectedGrams == null) return null;
    return amount * actualGrams / expectedGrams;
  }

  static double? _adequacyAmountInReferenceUnit(
    double amount, {
    required String nutrientId,
    required String actualUnit,
    required String expectedUnit,
  }) {
    final direct = _amountInReferenceUnit(
      amount,
      actualUnit: actualUnit,
      expectedUnit: expectedUnit,
    );
    if (direct != null) return direct;

    // FDA Supplement Facts Vitamin A amounts are declared in mcg RAE. DSLD
    // sometimes serializes that label unit as bare "mcg". It remains valid
    // for total-vitamin-A RDA/AI coverage, but this bridge is intentionally
    // confined to adequacy: the UL applies only to preformed Vitamin A, so
    // safety comparison still requires form lineage or a pipeline verdict.
    final id = _normalizeKey(nutrientId);
    final actual = normalizeDoseUnit(actualUnit);
    final expected = normalizeDoseUnit(expectedUnit);
    if (id == 'vitamin_a' && actual == 'mcg' && expected == 'mcg rae') {
      return amount;
    }
    return null;
  }

  static bool _unitMatchesReference(String actual, String expected) {
    final expectedUnit = normalizeDoseUnit(expected);
    if (expectedUnit.isEmpty) return true;
    final actualUnit = normalizeDoseUnit(actual);
    if (actualUnit.isEmpty) return false;
    if (actualUnit == expectedUnit) return true;

    // 'mcg'~'ug', 'mcg rae'~'ug rae', and 'mcg dfe'~'ug dfe' are no longer
    // listed here: normalizeDoseUnit() now folds the ASCII "ug" spelling to
    // "mcg" for both sides, so those pairs already compare equal above and
    // never reach this table. The remaining entries are genuine semantic
    // aliases (a plain mass unit standing in for a nutrient-specific form)
    // that no normalizer can fold away.
    const aliases = <String, Set<String>>{
      'mg alpha tocopherol': {'mg alpha-tocopherol', 'mg'},
      'mg ne': {'mg'},
    };
    return aliases[expectedUnit]?.contains(actualUnit) ?? false;
  }

  static String _normalizeKey(Object? raw) {
    return (raw ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  static bool _safeWordContains(String haystack, String needle) {
    if (haystack.length < 4 || needle.length < 4) return false;
    final escaped = RegExp.escape(needle);
    return RegExp('(^|[^a-z0-9])$escaped([^a-z0-9]|\$)').hasMatch(haystack);
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
