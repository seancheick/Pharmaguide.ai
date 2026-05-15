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
/// treatment downstream (blocked hides PersonalFit + ScoreBreakdown +
/// DeepDive; not-scored hides only ScoreBreakdown).
///
/// Verbatim mirror of production's `_isNotScored` method.
bool productIsNotScored(ProductsCoreData? product) {
  if (product == null) return false;
  final verdict = product.verdict ?? '';
  final score = product.score100Equivalent;
  final isBlocked = isUnsafeVerdict(verdict);
  return verdict.trim().toUpperCase() == 'NOT_SCORED' ||
      (score == null && !isBlocked);
}

/// PersonalFit card renders when product is not blocked. Production
/// sliver guard: `if (!isBlocked)` (line 301).
bool shouldShowPersonalFit({required bool isBlocked}) => !isBlocked;

/// ReviewBeforeUse card renders when product is not blocked. Production
/// sliver guard: `if (!isBlocked)` (line 349).
bool shouldShowReviewBeforeUse({required bool isBlocked}) => !isBlocked;

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

/// Legacy AllergenSummaryBanner fallback. Renders ONLY when:
///   • product is not blocked AND
///   • the product row carries a free-text allergenSummary AND
///   • the blob has NO structured allergens (which would have already
///     been rendered as personalized rows in ReviewBeforeUseCard)
///
/// Production sliver guard (line 508):
/// `if (!isBlocked && _product?.allergenSummary != null && matchAllergens(...).isEmpty)`
///
/// The caller computes the structured-allergen check via
/// `matchAllergens(...).isEmpty` and passes the result.
bool shouldShowAllergenSummaryBanner({
  required bool isBlocked,
  required String? allergenSummary,
  required bool noStructuredAllergens,
}) {
  if (isBlocked) return false;
  if (allergenSummary == null) return false;
  return noStructuredAllergens;
}
