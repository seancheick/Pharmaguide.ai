// Phase 11.7b.1 — Product Detail v2 conditional-rendering gates.
//
// Pure boolean functions, one per visibility decision the connected
// screen makes. No widget imports, no Riverpod — these are designed to
// be unit-tested with hand-written inputs.
//
// Each gate's name mirrors what production's sliver-level `if (...)`
// checks decide, so a parity reviewer can grep production for `if (!isBlocked`
// and find the corresponding v2 gate by name. The body of each function
// is the literal condition production uses; deviation here = clinical
// regression risk.
//
// Why these live alongside the connected screen rather than the
// production screen: production's gates are inline `if (...)` blocks
// inside its 3,022-line build method. Extracting them production-side
// would touch the production screen mid-rollout — the rule is "no
// production-side changes during v2 migration". Phase 11.11 cleanup
// extracts shared helpers (these + warnings pipeline) into a single
// module both screens consume.

import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/data/database/core_database.dart';

/// Whether the product carries a BLOCKED / UNSAFE verdict.
///
/// Production uses `isUnsafeVerdict(_product?.verdict)` inline; this
/// helper wraps it so callers don't need to import the verdict widget
/// just for one bool.
bool productIsBlocked(ProductsCoreData? product) =>
    isUnsafeVerdict(product?.verdict);

/// Whether the product is NOT_SCORED — explicitly "we don't have enough
/// mapped data to score this", distinct from blocked.
///
/// A blocked product has a clinical reason it shouldn't be used; a
/// not-scored product simply lacks coverage. They get different UI
/// treatment downstream (blocked hides Profile Relevance + ScoreBreakdown +
/// DeepDive; not-scored hides only ScoreBreakdown).
///
/// Verbatim mirror of production's `_isNotScored` method.
bool productIsNotScored(ProductsCoreData? product) {
  if (product == null) return false;
  final verdict = product.verdict ?? '';
  final score = product.qualityScoreV4100;
  final isBlocked = isUnsafeVerdict(verdict);
  return verdict.trim().toUpperCase() == 'NOT_SCORED' ||
      (score == null && !isBlocked);
}

/// Whether the product's label coverage is below the 0.3 trust floor
/// (`isLowCoverage` in core/scoring/coverage.dart — the shared
/// SAFETY-RULE contract). Distinct from [productIsNotScored]: a
/// low-coverage product may still carry a pipeline score, but no
/// surface may render that score as a confident tier-colored result.
/// Null product / null coverage counts as low (unknown ≠ trustworthy).
bool productHasLowCoverage(ProductsCoreData? product) =>
    isLowCoverage(product?.mappedCoverage);

/// Profile Relevance renders when product is not blocked. Blocked products
/// carry their safety message in the hero banner instead.
bool shouldShowProfileRelevance({required bool isBlocked}) => !isBlocked;

/// LabelConfidence card renders when:
///   • product is not blocked AND
///   • at least one of the 5 underlying signals fires
///     (mappedCoverage threshold, hasProprietaryBlends, isNotScored,
///      productStatus, unmappedActives)
///
/// Production sliver guard:
///   `if (!isBlocked && LabelConfidenceCard.hasAnySignal(...))` (line 403)
///
/// This helper takes the precomputed `hasAnySignal` so we don't
/// transitive-depend on the production LabelConfidenceCard widget here.
/// The connected screen calls `LabelConfidenceCard.hasAnySignal(...)`
/// and passes its result.
bool shouldShowLabelConfidence({
  required bool isBlocked,
  required bool hasAnySignal,
}) => !isBlocked && hasAnySignal;

/// ScoreBreakdown card renders when:
///   • product is not blocked AND
///   • product is not "NOT_SCORED" (no score to break down)
///
/// Production sliver guard: `if (!isBlocked && !isNotScored)` (line 428).
bool shouldShowScoreBreakdown({
  required bool isBlocked,
  required bool isNotScored,
}) => !isBlocked && !isNotScored;

/// DeepDive flattened sections (Ingredients through ManufacturerViolations)
/// render when:
///   • product is not blocked AND
///   • the detail blob is fully loaded (not loading, not errored)
///
/// Production sliver guard:
///   `if (!blobLoading && !blobError && !isBlocked)` (line 540)
bool shouldShowDeepDive({
  required bool isBlocked,
  required bool blobLoading,
  required bool blobError,
}) => !isBlocked && !blobLoading && !blobError;

/// Free-text allergen summary fallback. Renders ONLY when:
///   • product is not blocked AND
///   • the product row carries a free-text allergenSummary AND
///   • the blob has NO structured allergens (which would have already
///     been rendered as personalized rows in ReviewBeforeUseCard)
///
/// The caller computes the structured-allergen check from the detail
/// blob itself (`blob['allergens'] == null || blob['allergens'].isEmpty`)
/// and passes the result. Do NOT use `matchAllergens(...).isEmpty` as
/// the proxy — that is also true when the user has no allergens in
/// their profile, which would surface the fallback banner even though
/// structured rows were available.
bool shouldShowAllergenSummaryBanner({
  required bool isBlocked,
  required String? allergenSummary,
  required bool noStructuredAllergens,
}) {
  if (isBlocked) return false;
  if (allergenSummary == null) return false;
  return noStructuredAllergens;
}

/// "Allergen data unavailable" hedge — enforces the "unknown != safe" rule.
/// Shown ONLY when a user WITH declared allergens opens a non-blocked
/// product that carries NO allergen data at all (no structured allergens
/// AND no free-text summary). The absence of data must read as "we can't
/// confirm — check the label", never as a silent clean bill. Complements
/// [shouldShowAllergenSummaryBanner], which handles the has-free-text case.
///
/// Deliberately hedges toward caution: a user who opted into allergen
/// tracking is better served by a "check the label" reminder than by
/// silence on a product we have no allergen data for.
bool shouldShowAllergenDataUnavailableHedge({
  required bool isBlocked,
  required bool userHasAllergens,
  required bool noStructuredAllergens,
  required String? allergenSummary,
}) {
  if (isBlocked) return false;
  if (!userHasAllergens) return false;
  if (!noStructuredAllergens) return false;
  return allergenSummary == null || allergenSummary.trim().isEmpty;
}
