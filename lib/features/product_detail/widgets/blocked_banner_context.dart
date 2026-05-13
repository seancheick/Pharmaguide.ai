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
/// Voice — PharmaGuide brand voice per pharmaguide.io: conversational
/// yet authoritative, direct without alarm, clinical precision over
/// fear language. Knowledgeable peer-advisor with clinician backing.
///
///   - NO imperatives ("Stop", "Avoid", "Don't use", "Discontinue").
///   - NO emergency verbs; the danger-tone banner ("PharmaGuide does
///     not recommend this product") already carries the recommendation.
///   - Clinical precision: "active regulatory monitoring", "documented
///     labeling concerns", "lot-specific recall", "provider input".
///   - Frame negatives as actionable next steps, not absolutes.
///
/// Dr Pham's per-substance entries in banned_recalled_ingredients.json
/// DO use "Stop" / "Avoid" — but those flow through the bsd
/// `safety_warning_one_liner` / `safety_warning` fields verbatim. This
/// helper is the Flutter UI's surrounding context note, which uses
/// the PharmaGuide voice rather than mirroring authored imperatives.
///
/// Per the 2026-04-16 lesson on status overload (knowledge/lessons-
/// learned.md), conflating `substance` (the molecule itself is
/// controlled) with `adulterant_in_supplements` (a legitimate
/// prescription drug found undisclosed in supplements) is the
/// dangerous failure mode — a clinician-prescribed medication must
/// NOT read as "stop your medication." The adulterant note carries
/// the load-bearing reassurance: the drug itself is fine when
/// prescribed; the supplement is the concern.
///
/// The five enum values mirror assets/data/ban_context_vocab.json
/// (and pipeline scripts/data/banned_recalled_ingredients.json
/// `ban_context` field — live mix: substance=95, adulterant=29,
/// watchlist=12, contamination_recall=9, export_restricted=1):
///
///   - `substance`                 → no extra note (default tone)
///   - `adulterant_in_supplements` → "your prescription is separate"
///                                   reassurance
///   - `contamination_recall`      → "lot-specific recall, not the
///                                   substance itself"
///   - `watchlist`                 → "active regulatory monitoring"
///   - `export_restricted`         → "restricted abroad, legal in US"
///
/// Returns null for `substance`, null/absent input, or any unknown
/// value so callers safely skip rendering an empty row.
String? contextNoteFor(String? banContext) {
  switch (banContext?.trim().toLowerCase()) {
    case 'adulterant_in_supplements':
      return 'This is a prescription medication that has been found '
          'undeclared in some supplements. A conversation with your '
          'doctor is the right next step. If this drug has been '
          'prescribed for you, your prescription is separate from the '
          'concern about this supplement.';
    case 'contamination_recall':
      return 'This recall was driven by a contamination issue in '
          'specific product batches — not by the substance itself. '
          'Verifying the lot number with the manufacturer or your '
          'provider is the right next step.';
    case 'watchlist':
      return 'This ingredient sits on a regulatory watchlist where '
          'labeling concerns are under review. Worth a conversation '
          'with your doctor before considering this product.';
    case 'export_restricted':
      return 'This ingredient is restricted as a supplement in some '
          'countries while still being sold in the US. Worth a '
          'conversation with your doctor before considering this '
          'product.';
    default:
      return null;
  }
}
