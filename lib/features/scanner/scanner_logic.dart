// Typed catalog-safety helpers for scan confirmation and critical alerts.

import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/core/utils/product_canonical_ids.dart'
    as canonical_ids;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';

/// Two-state scan confirmation for [PGVerdictReveal].
///
/// Policy (v2): no per-tier judgement at scan time — only "recognized" vs
/// "recognized, worth reviewing on the product page". The flash fires before
/// any personal check, so "found" is never a safety colour.
///
///   no known catalog concern                  → found (brand accent)
///   blocked / unsafe / caution / not assessed → attention (amber)
///
/// Reads the typed catalog safety status, never a verdict string. The scan
/// flow passed the status id (`NO_KNOWN_CATALOG_CONCERN`) into a switch that
/// only knew verdicts, so every clean product flashed amber. The exhaustive
/// switch turns a new status into a compile error, not a silent amber.
PGVerdictKind scanRevealKind(CatalogProductSafetyStatus status) =>
    switch (status) {
      CatalogProductSafetyStatus.noKnownCatalogConcern => PGVerdictKind.found,
      CatalogProductSafetyStatus.blocked ||
      CatalogProductSafetyStatus.unsafe ||
      CatalogProductSafetyStatus.caution ||
      CatalogProductSafetyStatus.notAssessed => PGVerdictKind.attention,
    };

/// Whether a scanned product must be shown even when a guest is out of
/// scans: a blocked or unsafe catalog product, or one matched by a blocking
/// live recall alert. Matching reuses [SafetyAlert.appliesTo] with the same
/// canonical ids Stack uses, so the scan and the stack agree.
bool scanResultIsSafetyCritical(
  ProductsCoreData product, {
  Iterable<SafetyAlert> alerts = const [],
}) {
  if (catalogProductIsBlocked(product)) return true;
  final ingredientIds = canonical_ids.canonicalIdsForProduct(product);
  return alerts.any(
    (alert) =>
        alert.disposition == SafetyAlertDisposition.block &&
        alert.appliesTo(
          dsldId: product.dsldId,
          ingredientCanonicalIds: ingredientIds,
        ),
  );
}
