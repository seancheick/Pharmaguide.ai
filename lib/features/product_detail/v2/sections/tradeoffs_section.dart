// Phase 11.7d.3 — Tradeoffs section adapter.
//
// V2 mirror of production's `TradeoffsSection` (line 2101 in
// product_detail_screen.dart). Composes the v2 PGTradeoffsSection
// from blob['score_bonuses'] (positive) + blob['score_penalties']
// (negative).
//
// Production data path (verbatim port):
//   blob['score_bonuses']  → isPositive=true  → "What's good" column
//   blob['score_penalties'] → isPositive=false → "What to consider" column
//
// Each item: label || reason (headline) + detail || description (caption).
// Empty-label items are filtered out defensively. `sanitizeWhyDetail`
// drops noise patterns from the detail field.
//
// Sean's rules (2026-05-15):
//   • Preserve production gates: section hides when both lists are empty.
//   • Use production's sanitizeWhyDetail helper verbatim (publicly exposed).
//   • No invented copy — every headline/caption string comes from the
//     pipeline blob.
//   • Suppress cleanly on null/empty blob.
//
// Deferred to S7.next-iteration:
//   • Inactive-severity summary bullet (production T15 — "N ingredients
//     flagged for safety — review the list" — requires inactive list).
//   • T15 collapse of "Harmful additive X" → "Additives: X, Y, Z".
//   • Per-side cap (4 max) + "and N more" overflow toggle.
//   These are polish features atop the basic mapping; first pass
//   surfaces the full sanitized lists.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_tradeoffs_section.dart';
import 'package:pharmaguide/features/product_detail/product_detail_screen.dart'
    show sanitizeWhyDetail;

/// Build the Tradeoffs section. Returns `SizedBox.shrink()` when both
/// score_bonuses and score_penalties are empty/missing — matches
/// production's `whyItems.isEmpty` gate.
Widget buildTradeoffsSection({
  required Map<String, dynamic>? detailBlob,
}) {
  if (detailBlob == null) return const SizedBox.shrink();

  final bonuses = (detailBlob['score_bonuses'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList(growable: false) ??
      const [];
  final penalties = (detailBlob['score_penalties'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList(growable: false) ??
      const [];

  if (bonuses.isEmpty && penalties.isEmpty) return const SizedBox.shrink();

  final pros = bonuses
      .map(_toTradeoff)
      .where((t) => t.headline.trim().isNotEmpty)
      .toList(growable: false);
  final considerations = penalties
      .map(_toTradeoff)
      .where((t) => t.headline.trim().isNotEmpty)
      .toList(growable: false);

  if (pros.isEmpty && considerations.isEmpty) {
    return const SizedBox.shrink();
  }

  return PGTradeoffsSection(
    pros: pros,
    considerations: considerations,
  );
}

/// Map a raw bonus/penalty entry to a PGTradeoff. Verbatim port of
/// production's `_extractWhyItems` field resolution:
///   headline = label || reason
///   caption  = sanitizeWhyDetail(detail || description)
PGTradeoff _toTradeoff(Map<String, dynamic> entry) {
  final headline = (entry['label']?.toString() ??
          entry['reason']?.toString() ??
          '')
      .trim();
  final rawDetail =
      entry['detail']?.toString() ?? entry['description']?.toString();
  final caption = sanitizeWhyDetail(rawDetail);
  return PGTradeoff(
    headline: headline,
    caption: caption.isEmpty ? null : caption,
  );
}
