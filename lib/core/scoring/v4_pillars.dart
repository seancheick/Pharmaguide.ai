// Shared v4 six-pillar parsing — single source of truth for reading a
// detail blob's `quality_pillars_v4` map.
//
// Extracted from score_breakdown_section.dart so the Compare surface and
// the Score Breakdown section parse the SAME blob shape with the SAME
// spec (no second brain). Maxes match the pipeline
// (`scripts/scoring_v4/config/quality_score.json`); the blob also carries
// `max` per pillar, used in preference to the fallback.

import 'package:pharmaguide/core/utils/num_parse.dart';

/// v4 pillar key → (display label, fallback max) in display order.
const List<(String, String, int)> kV4PillarSpec = [
  ('formulation', 'Formulation', 20),
  ('dose', 'Dose', 20),
  ('evidence', 'Evidence', 20),
  ('transparency', 'Transparency', 15),
  ('verification', 'Testing & Brand', 15),
  ('safety_hygiene', 'Safety Hygiene', 10),
];

/// One parsed v4 pillar value — pure data, no widget types.
class V4PillarValue {
  /// Blob key, e.g. `formulation` / `safety_hygiene`.
  final String key;

  /// Display label, e.g. "Safety Hygiene".
  final String label;

  /// Pillar max — the blob's `max` when present, else the spec fallback.
  final int max;

  /// Raw pillar score on its own scale. Null when the blob omits it.
  final double? score;

  /// One-line `reason` from the blob, trimmed. Null when empty/missing.
  final String? reason;

  const V4PillarValue({
    required this.key,
    required this.label,
    required this.max,
    this.score,
    this.reason,
  });
}

/// True when [pillars] carries ALL six spec pillars — the contract every
/// v4 surface must verify before rendering native-scale arithmetic
/// ("= N/100" sum lines, paired compare rows). A partial parse (4/6
/// entries) would render a sum that contradicts the hero score, so
/// callers fall back (score breakdown → v3; compare → hide pillar rows).
bool hasAllV4Pillars(List<V4PillarValue> pillars) =>
    pillars.length == kV4PillarSpec.length;

/// Parse a blob's `quality_pillars_v4` map into the six pillars in
/// display order. Pillars whose entry is missing/malformed are skipped —
/// callers treat an incomplete result (see [hasAllV4Pillars]) as "no v4
/// data" and degrade (score breakdown shows unavailable; compare hides
/// the pillar rows).
///
/// Hardened (2026-06): scores accept num-or-numeric-string, `max <= 0`
/// falls back to the spec max (no NaN/Infinity bar math downstream),
/// and each entry parses inside its own try/catch — one malformed entry
/// skips that entry only (same pattern as warnings_pipeline).
List<V4PillarValue> parseV4Pillars(Map<String, dynamic>? pillarsBlob) {
  if (pillarsBlob == null) return const [];
  final out = <V4PillarValue>[];
  for (final (key, label, fallbackMax) in kV4PillarSpec) {
    try {
      final raw = pillarsBlob[key];
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final score = asFiniteDouble(m['score']);
      final rawMax = asFiniteDouble(m['max'])?.toInt();
      final max = (rawMax == null || rawMax <= 0) ? fallbackMax : rawMax;
      final reason = m['reason'] is String
          ? (m['reason'] as String).trim()
          : null;
      out.add(
        V4PillarValue(
          key: key,
          label: label,
          max: max,
          score: score,
          reason: (reason != null && reason.isNotEmpty) ? reason : null,
        ),
      );
      // One malformed entry must never take the other five down.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      continue;
    }
  }
  return out;
}
