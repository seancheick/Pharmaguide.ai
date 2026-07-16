// Better Alternatives ranker — Phase 11.7L.F.
//
// Replaces the score-only ranking in the original `findAlternatives`
// query (lib/data/database/core_database.dart) with a multi-tier
// scoring chain that respects intent, audience, and ingredient
// family — not just category-and-score.
//
// Sean's audit (knowledge/better-alternatives-audit.md) traced the
// production failures to four root causes:
//
//   1. Off-market products surfaced as "Higher quality alternatives"
//      (2,010 / 8,441 products are discontinued).
//   2. `primary_category` is the only intent signal, but
//      "multivitamin" alone covers 1,947 products of wildly
//      different `supplement_type`.
//   3. `>=` instead of `>` lets ties qualify as "higher".
//   4. Kids ↔ adult ↔ prenatal cross-recommends slip through.
//
// This module's contract:
//
//   * `rankAlternatives(current, candidates, …)` is **pure** — every
//     input is data, no DB / IO / Riverpod. Callers pass the current
//     product, a wider candidate pool, and (optionally) the user's
//     `goal_matches` set, and get back the top-N best alternatives.
//   * Hard filters run first (off-market, ≤-score, audience walls,
//     banned/recalled, sport↔general carveout). The remainder is
//     bucketed into 4 tiers and sorted within tier by a deterministic
//     tiebreaker chain.
//   * The ranker NEVER raises. It returns `[]` when no candidate
//     clears the hard filters.

import 'dart:convert';

import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/services/recommendations/audience_classifier.dart';

/// The default cap that callers use. UI surfaces 2-3; the buffer
/// gives the ranker headroom to substitute a top pick if a tier
/// returns empty.
const int kDefaultBetterAlternativesLimit = 3;

/// Pure ranker entrypoint. Given the current product and a candidate
/// pool, return the best alternatives ordered by tier + tiebreaker.
///
/// `candidates` should be a reasonably wide pool (30-50 items) so
/// the ranker has room to skip down through tiers. The recommended
/// pool is `CoreDatabase.fetchBetterAlternativesPool` (which already
/// applies on-market and strictly-higher-score gates at the SQL
/// layer) — but the ranker re-applies every hard filter as a defence
/// in depth.
///
/// `userGoals`, when non-empty, lets the goal-match tiebreaker
/// prefer candidates that align with the user's saved goals. Pass
/// the user's `SchemaIds.goals` set (sentinel-stripped). When empty
/// or null the goal-match tiebreaker is neutral.
List<ProductsCoreData> rankAlternatives({
  required ProductsCoreData current,
  required List<ProductsCoreData> candidates,
  Set<String>? userGoals,
  int limit = kDefaultBetterAlternativesLimit,
}) {
  if (candidates.isEmpty) return const [];

  final currentAudience = inferAudience(current);
  final currentFamily = _ingredientFamily(current);
  final currentGoals = _goalMatches(current);

  final ranked = <_RankedCandidate>[];

  for (final cand in candidates) {
    if (!_passesHardFilters(current, cand)) continue;

    final candAudience = inferAudience(cand);
    // Kids ↔ prenatal walls and same-specific cross-blocks.
    if (!isAudienceCompatible(currentAudience, candAudience)) continue;

    final candFamily = _ingredientFamily(cand);
    final familyJaccard = _jaccard(currentFamily, candFamily);

    // Sport ↔ general carve-out (HARD with ingredient-overlap
    // precondition). Block the swap unless the family Jaccard is at
    // least 0.5. Same-audience sport↔sport and general↔general are
    // unaffected.
    final isSportGeneralCross =
        (currentAudience == Audience.sport &&
            candAudience == Audience.general) ||
        (currentAudience == Audience.general && candAudience == Audience.sport);
    if (isSportGeneralCross && familyJaccard < 0.5) continue;

    // Goals Jaccard — if the user has saved goals, the candidate's
    // overlap with them is the relevant signal. Otherwise fall back
    // to the product-to-product goal-match overlap (when the catalog
    // populated both sides).
    final candGoals = _goalMatches(cand);
    final goalsJaccard = userGoals != null && userGoals.isNotEmpty
        ? _jaccard(userGoals, candGoals)
        : _jaccard(currentGoals, candGoals);

    final tier = _classifyTier(
      currentSupplementType: current.supplementType,
      candidateSupplementType: cand.supplementType,
      familyJaccard: familyJaccard,
      currentPrimaryCategory: current.primaryCategory,
      candidatePrimaryCategory: cand.primaryCategory,
    );
    if (tier == null) continue;

    // Demote when the audience is "specific but mismatched" — e.g.
    // current is men's, candidate is general. `isAudienceCompatible`
    // already let this through; we soft-demote by appending a half-
    // tier penalty so a same-audience candidate in a lower tier
    // still beats a cross-audience candidate in a higher tier.
    final audiencePenalty =
        (currentAudience != Audience.general && candAudience != currentAudience)
        ? 1
        : 0;

    ranked.add(
      _RankedCandidate(
        product: cand,
        tier: tier,
        audiencePenalty: audiencePenalty,
        familyJaccard: familyJaccard,
        goalsJaccard: goalsJaccard,
        allergenCompat: _allergenCompatibility(current, cand),
      ),
    );
  }

  if (ranked.isEmpty) return const [];

  // Sort by effective tier (tier + audiencePenalty), then by the
  // tiebreaker chain Sean approved:
  //   1. family Jaccard DESC
  //   2. goals Jaccard DESC
  //   3. v4 quality score DESC
  //   4. mapped_coverage DESC
  //   5. allergen compatibility DESC
  ranked.sort((a, b) {
    final aEff = a.tier + a.audiencePenalty;
    final bEff = b.tier + b.audiencePenalty;
    if (aEff != bEff) return aEff.compareTo(bEff);
    final fam = b.familyJaccard.compareTo(a.familyJaccard);
    if (fam != 0) return fam;
    final goals = b.goalsJaccard.compareTo(a.goalsJaccard);
    if (goals != 0) return goals;
    final score = (effectiveQualityScore(b.product) ?? 0).compareTo(
      effectiveQualityScore(a.product) ?? 0,
    );
    if (score != 0) return score;
    final coverage = (b.product.mappedCoverage ?? 0).compareTo(
      a.product.mappedCoverage ?? 0,
    );
    if (coverage != 0) return coverage;
    return b.allergenCompat.compareTo(a.allergenCompat);
  });

  return _takeDistinctProducts(ranked, limit);
}

List<ProductsCoreData> _takeDistinctProducts(
  List<_RankedCandidate> ranked,
  int limit,
) {
  if (limit <= 0) return const [];

  final out = <ProductsCoreData>[];
  final seen = <String>{};

  for (final candidate in ranked) {
    final key = _nearDuplicateKey(candidate.product);
    if (key != null && !seen.add(key)) continue;
    out.add(candidate.product);
    if (out.length >= limit) break;
  }

  return List.unmodifiable(out);
}

String? _nearDuplicateKey(ProductsCoreData product) {
  final brand = _dedupeToken(product.brandName);
  final name = _normalizedProductNameForDedupe(product.productName);
  if (brand.isEmpty || name.isEmpty) return null;

  final type = _dedupeToken(product.supplementType ?? product.primaryCategory);
  final family = _ingredientFamily(product).toList()..sort();
  final familyKey = family.join(',');

  return [brand, name, type, familyKey].join('|');
}

String _dedupeToken(String? value) {
  return value
          ?.trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim() ??
      '';
}

String _normalizedProductNameForDedupe(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(
        RegExp(
          r'\b\d+(?:\.\d+)?\s*(?:billion\s*cfu|million\s*cfu|capsules?|'
          r'tablets?|softgels?|gummies?|servings?|mg|mcg|ug|iu|g|grams?|cfu)\b',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

// =============================================================================
// Hard filters
// =============================================================================

/// Effective /100 quality score for ranking: the v4 canonical score.
/// Mirrors `CoreDatabase.effectiveScoreSql` so the pure ranker and SQL pool
/// agree on ordering.
double? effectiveQualityScore(ProductsCoreData p) => p.qualityScoreV4100;

/// True when a row is safety-suppressed (status present and not
/// 'scored' → BLOCKED/UNSAFE/NOT_SCORED).
bool isSafetySuppressed(ProductsCoreData p) {
  final s = p.qualityScoreStatus;
  return s != 'scored';
}

/// Hard filters every candidate must pass before audience and tier
/// checks. These mirror the SQL-side filters in
/// `fetchBetterAlternativesPool` so the ranker is safe to call on
/// any list (including a fixture set).
bool _passesHardFilters(ProductsCoreData current, ProductsCoreData candidate) {
  // No self-recommend.
  if (candidate.dsldId == current.dsldId) return false;
  // On-market only.
  final disc = candidate.discontinuedDate;
  if (disc != null && disc.trim().isNotEmpty) return false;
  // Never recommend a safety-suppressed product (BLOCKED/UNSAFE) — its
  // score is NULL and the product is unsafe.
  if (isSafetySuppressed(candidate)) return false;
  // Candidate must carry a score so the section can render a value.
  final candScore = effectiveQualityScore(candidate);
  if (candScore == null) return false;
  // Strictly higher than the current product — UNLESS the current
  // product is itself unscored. Phase 11.7L.F follow-up
  // (Sean 2026-05-16): blocked products may ship with no v4 score because the
  // safety verdict short-circuits scoring. The user landing on a banned
  // product NEEDS to see safer alternatives, so we treat "no score" as
  // "lower than anything that has a score" and let scored candidates pass.
  //
  // **Do NOT rewrite this branch to reject `curScore == null`.**
  // The user reason for being on this section is that the current
  // product is unsafe / unscored / blocked — a future cleanup that
  // "fixes" this back to a strict score comparison would silently
  // hide every alternative for the population that needs them most.
  // Policy in one line: blocked or unscored products may have no
  // quality score; any scored, on-market, non-blocked candidate is
  // considered preferable if it passes relevance ranking.
  final curScore = effectiveQualityScore(current);
  if (curScore != null && candScore <= curScore) return false;
  // Safety flags — never surface a banned/recalled candidate.
  if ((candidate.hasBannedSubstance ?? 0) == 1) return false;
  if ((candidate.hasRecalledIngredient ?? 0) == 1) return false;
  return true;
}

// =============================================================================
// Tier classification
// =============================================================================

/// Bucket assignment per the audit doc:
///
///   * Tier 0 = same `supplement_type` AND ingredient-family
///              Jaccard ≥ 0.5 — closest swap.
///   * Tier 1 = same `supplement_type` only.
///   * Tier 2 = ingredient-family Jaccard ≥ 0.5, different
///              `supplement_type` — same active family even if
///              presentation differs.
///   * Tier 3 = same `primary_category` only — last-resort fallback
///              (today's legacy behaviour).
///
/// Returns `null` when the candidate doesn't fit any tier (effectively
/// a soft-reject; the candidate is dropped from results).
int? _classifyTier({
  required String? currentSupplementType,
  required String? candidateSupplementType,
  required double familyJaccard,
  required String? currentPrimaryCategory,
  required String? candidatePrimaryCategory,
}) {
  final sameType = _equalIgnoreCase(
    currentSupplementType,
    candidateSupplementType,
  );
  final hasFamilyOverlap = familyJaccard >= 0.5;
  if (sameType && hasFamilyOverlap) return 0;
  if (sameType) return 1;
  if (hasFamilyOverlap) return 2;
  if (_equalIgnoreCase(currentPrimaryCategory, candidatePrimaryCategory)) {
    return 3;
  }
  return null;
}

// =============================================================================
// Ingredient-family extraction + Jaccard
// =============================================================================

/// Build the candidate's "ingredient family" set:
///
///   * lowercased entries from the JSON list in `key_ingredient_tags`,
///     when the field is populated (43% of the catalog as of
///     2026-05-16)
///   * synthetic markers from the `contains_*` boolean flags
///     (`contains_omega3`, `contains_probiotics`, `contains_collagen`,
///     `contains_adaptogens`, `contains_nootropics`, `is_probiotic`)
///
/// The boolean flags catch the case where `key_ingredient_tags` is
/// missing — e.g. a probiotic product without ingredient tags still
/// surfaces `is_probiotic = 1`, which lets the ranker keep it in
/// the right tier when compared against another probiotic.
Set<String> _ingredientFamily(ProductsCoreData product) {
  final out = <String>{};
  final raw = product.keyIngredientTags;
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final v in decoded) {
          if (v == null) continue;
          final s = v.toString().trim().toLowerCase();
          if (s.isNotEmpty) out.add(s);
        }
      }
    } on FormatException {
      // Pipeline shouldn't emit malformed JSON, but be defensive.
    }
  }
  if ((product.containsOmega3 ?? 0) == 1) out.add('flag:omega3');
  if ((product.containsProbiotics ?? 0) == 1) out.add('flag:probiotics');
  if ((product.containsCollagen ?? 0) == 1) out.add('flag:collagen');
  if ((product.containsAdaptogens ?? 0) == 1) out.add('flag:adaptogens');
  if ((product.containsNootropics ?? 0) == 1) out.add('flag:nootropics');
  if ((product.isProbiotic ?? 0) == 1) out.add('flag:probiotic');
  return out;
}

/// Build the candidate's `goal_matches` set (e.g.
/// `{'GOAL_SLEEP_QUALITY', 'GOAL_IMMUNE_SUPPORT'}`). Empty when
/// `goal_matches` is null / empty / malformed.
Set<String> _goalMatches(ProductsCoreData product) {
  final out = <String>{};
  final raw = product.goalMatches;
  if (raw == null || raw.isEmpty) return out;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      for (final v in decoded) {
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
    }
  } on FormatException {
    // Defensive.
  }
  return out;
}

/// Jaccard similarity: `|A ∩ B| / |A ∪ B|`. Returns 0 when both
/// sets are empty (no signal either way is treated as neutral).
double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty && b.isEmpty) return 0;
  final intersection = a.where(b.contains).length;
  final union = a.length + b.length - intersection;
  if (union == 0) return 0;
  return intersection / union;
}

/// `1.0` when the candidate preserves every allergen-free flag the
/// current product carries (so a gluten-free buyer doesn't lose
/// that property when swapping). `0.0` when the candidate breaks at
/// least one flag the current product had. Flags the current
/// product never claimed don't count — gaining a new "vegan" claim
/// is neutral, not a penalty.
double _allergenCompatibility(
  ProductsCoreData current,
  ProductsCoreData candidate,
) {
  bool flagPreserved(int? curFlag, int? candFlag) {
    if ((curFlag ?? 0) != 1) return true; // current didn't claim it
    return (candFlag ?? 0) == 1; // candidate must also claim it
  }

  final preserved = [
    flagPreserved(current.isGlutenFree, candidate.isGlutenFree),
    flagPreserved(current.isDairyFree, candidate.isDairyFree),
    flagPreserved(current.isSoyFree, candidate.isSoyFree),
    flagPreserved(current.isVegan, candidate.isVegan),
    flagPreserved(current.isVegetarian, candidate.isVegetarian),
    flagPreserved(current.isOrganic, candidate.isOrganic),
    flagPreserved(current.isNonGmo, candidate.isNonGmo),
  ];
  // Each flag carries equal weight; return the preserved fraction.
  // If the current product claimed nothing, every flag is `true` and
  // the score is 1.0 — no penalty.
  final ok = preserved.where((b) => b).length;
  return ok / preserved.length;
}

bool _equalIgnoreCase(String? a, String? b) {
  if (a == null || b == null) return false;
  return a.trim().toLowerCase() == b.trim().toLowerCase();
}

// =============================================================================
// Internal struct
// =============================================================================

class _RankedCandidate {
  final ProductsCoreData product;
  final int tier;
  final int audiencePenalty;
  final double familyJaccard;
  final double goalsJaccard;
  final double allergenCompat;

  const _RankedCandidate({
    required this.product,
    required this.tier,
    required this.audiencePenalty,
    required this.familyJaccard,
    required this.goalsJaccard,
    required this.allergenCompat,
  });
}
