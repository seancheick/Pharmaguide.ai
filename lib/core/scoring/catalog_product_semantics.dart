import 'package:pharmaguide/core/widgets/verdict_badge.dart';
import 'package:pharmaguide/data/database/core_database.dart';

/// Catalog-level product safety, independent of quality and personalization.
enum CatalogProductSafetyStatus {
  blocked,
  unsafe,
  caution,
  noKnownCatalogConcern,
  notAssessed,
}

/// Completion state for the catalog assessment.
enum CatalogAssessmentStatus { complete, partial, failed }

/// Consumer-facing limited-assessment cue for every quality-score surface.
///
/// Routine internal bands stay out of the consumer UI. Low and unknown bands
/// fail closed to Limited so a future enum cannot accidentally overstate
/// confidence in an older app.
String? catalogScoreConfidenceLabel(String? confidence) {
  final normalized = confidence?.trim().toLowerCase().replaceAll('-', '_');
  if (normalized == null || normalized.isEmpty) return null;
  switch (normalized) {
    case 'high':
    case 'moderate':
    case 'medium':
      return null;
    case 'low':
    case 'limited':
    case 'very_low':
      return 'Limited';
    default:
      return 'Limited';
  }
}

String catalogProductSafetyStatusId(CatalogProductSafetyStatus status) =>
    switch (status) {
      CatalogProductSafetyStatus.blocked => 'BLOCKED',
      CatalogProductSafetyStatus.unsafe => 'UNSAFE',
      CatalogProductSafetyStatus.caution => 'CAUTION',
      CatalogProductSafetyStatus.noKnownCatalogConcern =>
        'NO_KNOWN_CATALOG_CONCERN',
      CatalogProductSafetyStatus.notAssessed => 'NOT_ASSESSED',
    };

CatalogProductSafetyStatus catalogProductSafetyStatus(
  ProductsCoreData product,
) {
  final productSafetyStatus = product.productSafetyStatus?.trim().toLowerCase();
  switch (productSafetyStatus) {
    case 'blocked':
      return CatalogProductSafetyStatus.blocked;
    case 'unsafe':
      return CatalogProductSafetyStatus.unsafe;
    case 'caution':
      return CatalogProductSafetyStatus.caution;
    case 'no_known_catalog_concern':
      return CatalogProductSafetyStatus.noKnownCatalogConcern;
    case 'not_assessed':
      return CatalogProductSafetyStatus.notAssessed;
  }
  if (productSafetyStatus?.isNotEmpty == true) {
    // A populated but unknown new-contract value is schema drift. Never let
    // the legacy verdict turn that uncertainty into a positive state.
    return CatalogProductSafetyStatus.notAssessed;
  }

  // Additive-schema fallback for catalogs older than export schema 2.2.0.
  // POOR is quality-only and therefore maps to no catalog safety concern.
  switch (product.verdict?.trim().toUpperCase()) {
    case 'BLOCKED':
      return CatalogProductSafetyStatus.blocked;
    case 'UNSAFE':
      return CatalogProductSafetyStatus.unsafe;
    case 'CAUTION':
      return CatalogProductSafetyStatus.caution;
    case 'SAFE':
    case 'POOR':
      return CatalogProductSafetyStatus.noKnownCatalogConcern;
    default:
      return CatalogProductSafetyStatus.notAssessed;
  }
}

CatalogAssessmentStatus catalogAssessmentStatus(ProductsCoreData product) {
  final assessmentStatus = product.qualityAssessmentStatus
      ?.trim()
      .toLowerCase();
  switch (assessmentStatus) {
    case 'complete':
      return CatalogAssessmentStatus.complete;
    case 'partial':
      return CatalogAssessmentStatus.partial;
    case 'failed':
      return CatalogAssessmentStatus.failed;
  }
  if (assessmentStatus?.isNotEmpty == true) {
    return CatalogAssessmentStatus.failed;
  }

  // Additive-schema fallback for older snapshots.
  switch (product.qualityScoreStatus?.trim().toLowerCase()) {
    case 'scored':
    case 'suppressed_safety':
      return CatalogAssessmentStatus.complete;
    case 'not_scored':
      return CatalogAssessmentStatus.partial;
  }
  return product.qualityScoreV4100 == null
      ? CatalogAssessmentStatus.partial
      : CatalogAssessmentStatus.complete;
}

bool catalogProductIsBlocked(ProductsCoreData? product) {
  if (product == null) return false;
  final status = catalogProductSafetyStatus(product);
  return status == CatalogProductSafetyStatus.blocked ||
      status == CatalogProductSafetyStatus.unsafe;
}

/// Whether the catalog assessment is incomplete while a number still exists.
///
/// This is the `scored` + `partial` combination, and it is a real, honest
/// state: the engine computed a total while a pillar the rubric requires was
/// never assessed. On the 2026.09.19 catalog that is 4,117 products whose
/// Evidence pillar contributed 0 of 20 because no reviewed record matched any
/// active on the label — not because a review concluded zero.
///
/// Such a product is NOT "not scored": it has five assessed pillars worth
/// showing. What it must never do is publish a definitive tier, because the
/// unassessed pillar leaves the true total spanning a 20-point band that
/// crosses a tier boundary for 98.9% of them.
///
/// Distinct from [catalogProductIsNotScored], which means there is no usable
/// number at all.
bool catalogProductAssessmentIncomplete(ProductsCoreData? product) {
  if (product == null) return false;
  if (catalogProductIsNotScored(product)) return false;
  return catalogAssessmentStatus(product) != CatalogAssessmentStatus.complete;
}

/// Whether a completed public quality verdict may be shown for this product.
///
/// The single predicate every eligibility surface should ask — ranking,
/// recommendations, sharing, "high quality" filters, stack scoring. A product
/// qualifies only when it is not blocked, has a usable number, AND the
/// assessment behind that number actually finished.
bool catalogProductHasCompletePublicScore(ProductsCoreData? product) {
  if (product == null) return false;
  if (catalogProductIsBlocked(product)) return false;
  if (catalogProductIsNotScored(product)) return false;
  return catalogAssessmentStatus(product) == CatalogAssessmentStatus.complete;
}

/// Whether the catalog has no usable quality number for this product.
///
/// Narrow by design. A `partial` assessment is deliberately NOT not-scored:
/// conflating them was the root defect — it hid five genuinely assessed
/// pillars behind a "not enough verified data to score" message that blamed
/// the label for a review PharmaGuide had not performed. Completion is asked
/// separately via [catalogProductAssessmentIncomplete].
bool catalogProductIsNotScored(ProductsCoreData? product) {
  if (product == null) return false;

  final assessmentStatus = product.qualityAssessmentStatus?.trim();
  final hasAssessmentStatus = assessmentStatus?.isNotEmpty == true;
  if (hasAssessmentStatus &&
      catalogAssessmentStatus(product) == CatalogAssessmentStatus.failed) {
    // A FAILED assessment yields nothing trustworthy to show. `partial`
    // deliberately does NOT return here: it falls through to the score-status
    // checks below and stays "scored" whenever a number exists, so its five
    // assessed pillars still render.
    return true;
  }

  final scoreStatus = product.qualityScoreStatus?.trim().toLowerCase();
  switch (scoreStatus) {
    case 'not_scored':
      return true;
    case 'suppressed_safety':
      return false;
    case 'scored':
      // A completed public score requires the public numeric value. This
      // fail-closed check mirrors the release gate for mixed-version caches.
      return product.qualityScoreV4100 == null;
  }
  if (scoreStatus?.isNotEmpty == true) {
    // Populated but unknown new-contract values are schema drift.
    return true;
  }

  if (hasAssessmentStatus) {
    // A complete assessment without a score-status field can occur during an
    // additive-schema transition. Keep the numeric value only when present.
    return product.qualityScoreV4100 == null;
  }

  // Legacy verdict and null-score fallback for catalogs older than 2.2.0.
  final verdict = product.verdict ?? '';
  return verdict.trim().toUpperCase() == 'NOT_SCORED' ||
      (product.qualityScoreV4100 == null && !isUnsafeVerdict(verdict));
}
