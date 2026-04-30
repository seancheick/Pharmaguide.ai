// Inactive-ingredient color rubric.
//
// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T16.
//
// Sean's design contract: when the user expands the full inactives
// list, each entry should be color-dotted so penalties (red),
// watchlist items (orange), neutral entries (yellow), and standard
// manufacturing components (green) are visible at a glance.
//
// V1 implementation:
//   - Whitelist (green): defers to `standard_excipients.dart`'s
//     `isWhitelistedExcipient(name)` — that's our existing source of
//     truth for "this is a normal manufacturing component."
//   - Red: a curated set of additives that score_penalties commonly
//     flag (artificial dyes, sweeteners, syrups). Pipeline doesn't
//     ship a per-ingredient concern level, so the table is hand-
//     maintained. Backlog item to enrich from pipeline data.
//   - Orange: watchlist (palm oil, partially hydrogenated, etc.).
//   - Yellow: anything else (acceptable but worth noting).

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/data/standard_excipients.dart';

/// Visual tone for an inactive ingredient's color dot. Maps cleanly
/// to a 4-stop palette (green = best, red = worst).
enum InactiveTone { green, yellow, orange, red }

/// Curated set of inactive names that should render with the **red**
/// (penalty) tone. Lowercase + trimmed for case-insensitive lookup.
/// V1 — covers the most common "what's bad on labels" set Sean
/// flagged in the walkthrough; pipeline-driven concern data lands
/// in a future enrichment pass (backlog).
const Set<String> _redInactives = {
  // Artificial sweeteners
  'aspartame',
  'sucralose',
  'saccharin',
  'acesulfame potassium',
  'acesulfame-k',
  // Common syrups / sugars
  'high fructose corn syrup',
  'corn syrup',
  'sugar syrup',
  // Artificial dyes
  'red 40',
  'red 3',
  'yellow 5',
  'yellow 6',
  'blue 1',
  'blue 2',
  'green 3',
  'fd&c red no. 40',
  'fd&c yellow no. 5',
  'fd&c yellow no. 6',
  'fd&c blue no. 1',
  // Partially hydrogenated oils (trans fats)
  'partially hydrogenated soybean oil',
  'partially hydrogenated cottonseed oil',
  // BHA / BHT preservatives flagged by FDA
  'bha',
  'bht',
  'butylated hydroxyanisole',
  'butylated hydroxytoluene',
};

/// Curated **orange** (watchlist) — entries that aren't outright
/// penalties but show up in score_penalties for some products.
const Set<String> _orangeInactives = {
  'palm oil',
  'palm kernel oil',
  'hydrogenated palm oil',
  'titanium dioxide',
  'carrageenan',
  'potassium sorbate',
  'sodium benzoate',
  'polysorbate 80',
  'soy lecithin',
};

/// Map an inactive ingredient name to its visual tone. Lowercase +
/// trimmed lookup against the whitelist + red + orange sets;
/// everything else falls through to [InactiveTone.yellow].
InactiveTone inactiveColorRank(String name) {
  final normalized = name.trim().toLowerCase();
  if (normalized.isEmpty) return InactiveTone.yellow;
  if (_redInactives.contains(normalized)) return InactiveTone.red;
  if (_orangeInactives.contains(normalized)) return InactiveTone.orange;
  if (isWhitelistedExcipient(normalized)) return InactiveTone.green;
  return InactiveTone.yellow;
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
