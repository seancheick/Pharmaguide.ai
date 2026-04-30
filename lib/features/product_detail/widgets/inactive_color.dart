// Inactive-ingredient color rubric.
//
// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T16 +
// 2026-04-30 follow-up (pipeline-driven severity).
//
// **2026-04-30 — clean cut to pipeline-driven severity.**
//
// Pre-cut, this file maintained two hand-curated sets (`_redInactives`,
// `_orangeInactives`) plus a whitelist-based green fallback. The
// pipeline now ships per-ingredient `severity_level` populated from
// `harmful_additives.json` (clinician-curated, 115 entries). Sean's
// call: "harmful_additives.json already covers the high-signal cases
// (talc, TiO2, artificial colors, BHA/BHT, etc.) with curated severity
// from clinical sources. Keeping a parallel hardcoded list creates two
// sources of truth for 'is this scary?' and they will drift."
//
// Mapping (per pipeline `severity_level_definitions`):
//   "high"     → 🔴 red    — restricted/banned/strong harm evidence
//   "moderate" → 🟠 orange — debated, credible risk under conditions
//   "low"      → 🟡 yellow — minor / theoretical concern
//   ""/missing → 🟢 green  — no penalty, standard component
//   "none"     → 🟢 green  — defensive only, doesn't appear in
//                            current pipeline data

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Visual tone for an inactive ingredient's color dot. Maps cleanly
/// to a 4-stop palette (green = best, red = worst).
enum InactiveTone { green, yellow, orange, red }

/// Map an inactive ingredient row to its visual tone.
///
/// Reads `inactive['severity_level']` (always present in the pipeline
/// blob; empty string when the ingredient isn't in
/// `harmful_additives.json`). Case-insensitive match against `"high"`,
/// `"moderate"`, `"low"`. Anything else → green.
InactiveTone inactiveColorRank(Map<String, dynamic> inactive) {
  final raw = inactive['severity_level'];
  final sev = raw is String ? raw.trim().toLowerCase() : '';
  switch (sev) {
    case 'high':
      return InactiveTone.red;
    case 'moderate':
      return InactiveTone.orange;
    case 'low':
      return InactiveTone.yellow;
    default:
      // Empty / "none" / unknown → green. Pipeline emits "" for
      // non-harmful rows; defensive fallback for anything else.
      return InactiveTone.green;
  }
}

/// Theme-side color for each tone. Lives here (rather than in a
/// shared palette file) because the rubric is tied to this widget's
/// semantics — green/yellow/orange/red as severity, not as hue.
extension InactiveToneColor on InactiveTone {
  Color get color {
    switch (this) {
      case InactiveTone.green:
        return AppTheme.severitySafe;
      case InactiveTone.yellow:
        return AppTheme.severityCaution;
      case InactiveTone.orange:
        return AppTheme.severityAvoid;
      case InactiveTone.red:
        return AppTheme.severityContraindicated;
    }
  }
}
