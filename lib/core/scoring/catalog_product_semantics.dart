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

/// Consumer-facing confidence vocabulary for every quality-score surface.
///
/// Missing data stays absent. Any populated value outside the known contract
/// fails closed to Limited so a future enum cannot accidentally overstate
/// confidence in an older app.
String? catalogScoreConfidenceLabel(String? confidence) {
  final normalized = confidence?.trim().toLowerCase().replaceAll('-', '_');
  if (normalized == null || normalized.isEmpty) return null;
  switch (normalized) {
    case 'high':
      return 'High';
    case 'moderate':
    case 'medium':
      return 'Moderate';
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

bool catalogProductIsNotScored(ProductsCoreData? product) {
  if (product == null) return false;

  final assessmentStatus = product.qualityAssessmentStatus?.trim();
  final hasAssessmentStatus = assessmentStatus?.isNotEmpty == true;
  if (hasAssessmentStatus &&
      catalogAssessmentStatus(product) != CatalogAssessmentStatus.complete) {
    // The independent completion state is authoritative. A stale "scored"
    // field or numeric value must not turn a partial/failed assessment into a
    // completed one.
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
