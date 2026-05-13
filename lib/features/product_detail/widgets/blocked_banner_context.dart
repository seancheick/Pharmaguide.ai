import 'package:intl/intl.dart';

/// Sprint C (2026-05-13) — helpers for the blocked-product banner's
/// new context-field rendering. Extracted so they're unit-testable
/// without spinning up the full product-detail screen + Drift
/// providers + Riverpod overrides. Both functions are pure: given
/// the pipeline's `banned_substance_detail` shape, they return the
/// user-facing string (or null when the input is absent/empty).

/// Assemble the regulatory line ("FDA ban effective · Sep 7, 2016")
/// from the pipeline's [regulatory_date_label] and [date] fields.
///
/// Rules:
///   - Returns null when the label is missing or whitespace. Orphan
///     dates without a regulatory verb ("2016-09-07" alone) carry no
///     context and would read as a footer mystery — better suppressed.
///   - When the label is present but the date is missing, returns
///     the label alone ("FDA ban effective").
///   - ISO 8601 dates ("YYYY-MM-DD") are parsed and rendered via
///     [DateFormat.yMMMd] → "Sep 7, 2016".
///   - Anything else (mis-formed date) falls back to the raw string
///     so the user still sees the regulator's intent.
String? buildRegulatoryLine(String? rawLabel, String? rawDate) {
  final label = rawLabel?.trim() ?? '';
  final date = rawDate?.trim() ?? '';
  if (label.isEmpty) return null;
  if (date.isEmpty) return label;
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return '$label · $date';
  return '$label · ${DateFormat.yMMMd().format(parsed)}';
}

/// Branch user-facing context on the pipeline's `ban_context` enum.
///
/// Voice matches the authored entries in
/// scripts/data/banned_recalled_ingredients.json (Dr Pham): short,
/// declarative, calm. "Stop", "Talk to your doctor", "Consult your
/// doctor" — informational, not alarming. The phrasings here are
/// the generic counterparts of her per-substance per-ban_context
/// idioms (see Meloxicam, Metformin → "Does not affect prescribed
/// [drug]"; 7-Keto DHEA, DHEA → "Restricted as a supplement
/// ingredient in [countries]…"; Anatabine, Orange B → "Associated
/// with labeling… should be avoided").
///
/// Per the 2026-04-16 lesson on status overload (knowledge/lessons-
/// learned.md), conflating `substance` (the molecule itself is
/// controlled) with `adulterant_in_supplements` (a legitimate
/// prescription drug found undisclosed in supplements) is the
/// dangerous failure mode — a clinician-prescribed medication that
/// appears in this category must NOT read as "stop your medication."
/// The adulterant note carries the load-bearing reassurance: the
/// drug itself is fine when prescribed; the supplement is the issue.
///
/// The four enum values mirror banned_recalled_ingredients.json:
///   - `substance`                 → no extra note (default tone)
///   - `adulterant_in_supplements` → "Does not affect this drug when
///                                   prescribed for you" reassurance
///   - `watchlist`                 → "associated with labeling concerns"
///   - `export_restricted`         → "Restricted abroad, still sold US"
///
/// Returns null for `substance`, null/absent input, or any unknown
/// value so callers safely skip rendering an empty row.
String? contextNoteFor(String? banContext) {
  switch (banContext?.trim().toLowerCase()) {
    case 'adulterant_in_supplements':
      return 'A prescription medication found undeclared in some '
          'supplements. Stop the supplement and talk to your doctor. '
          'Does not affect this drug when prescribed for you.';
    case 'watchlist':
      return 'On a regulatory watchlist — associated with labeling '
          'concerns. Talk to your doctor before use.';
    case 'export_restricted':
      return 'Restricted as a supplement ingredient in some countries '
          'while still sold in the US. Consult your doctor before use.';
    default:
      return null;
  }
}
