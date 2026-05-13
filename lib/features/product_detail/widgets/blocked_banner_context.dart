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
/// Per the 2026-04-16 lesson on status overload (knowledge/lessons-
/// learned.md), conflating `substance` (the molecule itself is
/// controlled) with `adulterant_in_supplements` (a legitimate
/// prescription drug found undisclosed in supplements) is the
/// dangerous failure mode — a clinician-prescribed medication that
/// appears in this category must NOT read as "stop your medication."
///
/// The four enum values mirror banned_recalled_ingredients.json:
///   - `substance`                 → no extra note (default tone)
///   - `adulterant_in_supplements` → "keep your prescription" guidance
///   - `watchlist`                 → "under regulatory review"
///   - `export_restricted`        → "restricted in some regions"
///
/// Returns null for `substance`, null/absent input, or any unknown
/// value so callers safely skip rendering an empty row.
String? contextNoteFor(String? banContext) {
  switch (banContext?.trim().toLowerCase()) {
    case 'adulterant_in_supplements':
      return 'This is a prescription medication that has been found '
          'undisclosed in some supplements. If a clinician has '
          'prescribed it to you, keep taking it as directed — the '
          'concern is the supplement, not the medication.';
    case 'watchlist':
      return 'This ingredient is under active regulatory review.';
    case 'export_restricted':
      return 'This ingredient is restricted in some regions.';
    default:
      return null;
  }
}
