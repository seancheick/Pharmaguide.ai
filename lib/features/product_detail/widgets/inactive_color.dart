// Inactive-ingredient color rubric.
//
// v1.5.0 canonical contract — Flutter reads `severity_status` from the
// pipeline (single routing decision baked at build time) and renders
// directly. The pipeline's mapping:
//   critical      → 🔴 red    — moderate/high/critical hazard, always show
//   informational → 🟠 orange — flagged but not hazardous on its own
//   suppress      → 🟡 yellow — low-severity excipient (silicon dioxide,
//                                MCC) tracked for transparency only
//   n/a           → 🟢 green  — non-additive or non-harmful inactive
//
// Legacy `severity_level` is read as a fallback for blobs built before
// the v1.5.0 refactor and removed once consumers migrate.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Visual tone for an inactive ingredient's color dot. Maps cleanly
/// to a 4-stop palette (green = best, red = worst).
enum InactiveTone { green, yellow, orange, red }

/// Map an inactive ingredient row to its visual tone.
///
/// Prefers the v1.5.0 `severity_status` enum (canonical). Falls back
/// to legacy `severity_level` for stale blobs.
InactiveTone inactiveColorRank(Map<String, dynamic> inactive) {
  final statusRaw = inactive['severity_status'];
  if (statusRaw is String && statusRaw.trim().isNotEmpty) {
    switch (statusRaw.trim().toLowerCase()) {
      case 'critical':
        return InactiveTone.red;
      case 'informational':
        return InactiveTone.orange;
      case 'suppress':
        return InactiveTone.yellow;
      case 'n/a':
        return InactiveTone.green;
    }
  }
  // Stale-blob fallback — pipeline retired severity_level in favor of
  // severity_status. harmful_severity (the same low/moderate/high enum)
  // is the surviving raw signal, kept on the inactive row, so cached
  // blobs without severity_status can still color via this read.
  final raw = inactive['harmful_severity'];
  final sev = raw is String ? raw.trim().toLowerCase() : '';
  switch (sev) {
    case 'high':
      return InactiveTone.red;
    case 'moderate':
      return InactiveTone.orange;
    case 'low':
      return InactiveTone.yellow;
    default:
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
