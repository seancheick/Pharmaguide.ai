// Pure helpers for the scanner screen. Extracted so the verdict-to-color
// policy can be unit-tested without pumping a full widget tree.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';
import 'package:pharmaguide/core/scoring/catalog_product_semantics.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';

/// Return the flash color associated with a scanned product's verdict
/// string. Case-insensitive; null and unrecognized values stay neutral.
///
/// Policy:
///   SAFE / GOOD / RECOMMENDED   → safe
///   CAUTION / REVIEW / MODERATE → caution
///   POOR                        → Poor quality-tier color (quality, not safety)
///   BLOCKED / UNSAFE            → contraindicated
///   NOT_SCORED / NUTRITION_ONLY → neutral
///   null / unknown              → neutral (not green)
///
/// Kept for callers/tests that still need a solid color; production
/// scan confirmation uses [verdictRevealKind] + [PGVerdictReveal].
Color verdictFlashColor(V2Palette p, String? verdict) {
  switch (verdict?.trim().toUpperCase()) {
    case 'RECOMMENDED':
    case 'SAFE':
    case 'GOOD':
      return p.safe;
    case 'CAUTION':
    case 'MODERATE':
    case 'REVIEW':
      return p.caution;
    case 'POOR':
      return VerdictBadge.poorQualityTone(p);
    case 'BLOCKED':
    case 'UNSAFE':
      return p.contraindicated;
    case 'NOT_SCORED':
    case 'NUTRITION_ONLY':
    default:
      return p.fgSubtle;
  }
}

/// Two-state scan confirmation for [PGVerdictReveal].
///
/// Policy (v2): no per-tier judgement at scan time — only "recognized,
/// looks clean" vs "recognized, worth reviewing on the product page".
///
///   no known catalog concern                  → success (green)
///   blocked / unsafe / caution / not assessed → attention (amber)
///
/// Reads the typed catalog safety status, never a verdict string. The scan
/// flow passed the status id (`NO_KNOWN_CATALOG_CONCERN`) into a switch that
/// only knew verdicts, so every clean product flashed amber. The exhaustive
/// switch turns a new status into a compile error, not a silent amber.
PGVerdictKind scanRevealKind(CatalogProductSafetyStatus status) =>
    switch (status) {
      CatalogProductSafetyStatus.noKnownCatalogConcern => PGVerdictKind.success,
      CatalogProductSafetyStatus.blocked ||
      CatalogProductSafetyStatus.unsafe ||
      CatalogProductSafetyStatus.caution ||
      CatalogProductSafetyStatus.notAssessed => PGVerdictKind.attention,
    };
