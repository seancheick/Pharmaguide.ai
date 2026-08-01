// Inactive-ingredient color rubric.
//
// v1.6.x canonical contract — Flutter reads `display_tone` from the pipeline
// (single routing decision baked at build time) and renders directly. The dot
// reflects the harmful-additive penalty B1 ACTUALLY applied (post-exemption),
// NOT the additive's file severity — so a 0-penalty capsule shell reads green
// while disclosed maltodextrin (0.5) reads light orange. The pipeline's mapping:
//   green        → 🟢 green  — 0 penalty AND no safety/regulatory concern
//   light_orange → 🟡 amber  — low additive penalty actually applied (~0.5)
//   dark_orange  → 🟠 orange — moderate additive penalty (~1.0)
//   red          → 🔴 red    — high/critical additive, or ANY banned_recalled
//                              (banned/recalled/high_risk/watchlist) signal
//
// Falls back to `severity_status`, then legacy `harmful_severity`, for blobs
// built before display_tone existed (offline cache).

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';

/// Visual tone for an inactive ingredient's color dot. Maps cleanly
/// to a 4-stop palette (green = best, red = worst).
enum InactiveTone { green, yellow, orange, red }

/// Map an inactive ingredient row to its visual tone.
///
/// Prefers the v1.6.x penalty-aware `display_tone` (canonical). Falls back to
/// `severity_status`, then legacy `harmful_severity`, for blobs built before
/// display_tone existed.
InactiveTone inactiveColorRank(Map<String, dynamic> inactive) {
  // Penalty-aware tone baked by the pipeline. Preferred over severity_status so
  // a 0-penalty excipient (e.g. a capsule shell) reads green, not amber.
  final toneRaw = inactive['display_tone'];
  if (toneRaw is String && toneRaw.trim().isNotEmpty) {
    switch (toneRaw.trim().toLowerCase()) {
      case 'red':
        return InactiveTone.red;
      case 'dark_orange':
        return InactiveTone.orange;
      case 'light_orange':
        return InactiveTone.yellow;
      case 'green':
        return InactiveTone.green;
    }
  }
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
  /// Takes the palette: an enum has no element tree, but its colour still
  /// has to follow brightness.
  Color color(V2Palette p) {
    switch (this) {
      case InactiveTone.green:
        return p.safe;
      case InactiveTone.yellow:
        return p.caution;
      case InactiveTone.orange:
        return p.avoid;
      case InactiveTone.red:
        return p.contraindicated;
    }
  }
}
