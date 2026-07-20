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

/// Named in-page destinations for the three navigable pillars only. Formulation,
/// Dose, and Safety Hygiene are explained in place and never link out (no dead
/// "See details" navigation). Keyed by pillar blob key.
const Map<String, String> kV4PillarActionLabels = {
  'evidence': 'View clinical evidence',
  'verification': 'View certifications',
  'transparency': 'View label details',
};

/// Consumer presentation status for one pillar, derived from its fraction of max.
enum V4PillarStatus { strong, mixed, limited }

/// Map a pillar's score/max to a presentation status. `>= 85%` Strong,
/// `>= 60%` Mixed, else Limited. A null score or non-positive max degrades to
/// Limited so we never overstate a pillar we could not read (fail-safe).
V4PillarStatus statusForPillar(double? score, int max) {
  if (score == null || max <= 0) return V4PillarStatus.limited;
  final pct = score / max;
  if (pct >= 0.85) return V4PillarStatus.strong;
  if (pct >= 0.60) return V4PillarStatus.mixed;
  return V4PillarStatus.limited;
}

/// Consumer copy for a [V4PillarStatus].
String v4PillarStatusLabel(V4PillarStatus status) => switch (status) {
  V4PillarStatus.strong => 'Strong',
  V4PillarStatus.mixed => 'Mixed',
  V4PillarStatus.limited => 'Limited',
};

/// One pipeline-authored explanation fact for a pillar. Pure display data —
/// the pipeline owns the copy; the app renders [valueDisplay] verbatim and never
/// synthesizes rationale of its own.
class V4PillarFact {
  /// Stable fact id, e.g. `epa_dha_per_day`.
  final String id;

  /// Short label, e.g. "EPA + DHA per day". Never empty.
  final String label;

  /// Consumer-ready value string from the pipeline contract's `value_display`,
  /// e.g. "660 mg/day". Never empty (a fact with no `value_display` is dropped
  /// as malformed).
  final String valueDisplay;

  /// Optional pipeline-authored context for the fact.
  final String? detail;

  const V4PillarFact({
    required this.id,
    required this.label,
    required this.valueDisplay,
    this.detail,
  });
}

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

  /// Pipeline-authored explanation facts (schema v1). Empty for old blobs and
  /// pillars without facts.
  final List<V4PillarFact> facts;

  const V4PillarValue({
    required this.key,
    required this.label,
    required this.max,
    this.score,
    this.reason,
    this.facts = const [],
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
          facts: _parseFacts(m['explanation']),
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

/// Parse a pillar's `explanation` block into facts. Only `schema_version == 1`
/// is honored; any other version (or a missing/malformed block) yields no
/// facts, keeping old blobs valid. Each fact must carry a non-empty `id` and
/// `value_display`; malformed facts are dropped individually, and pipeline strings
/// are preserved verbatim.
List<V4PillarFact> _parseFacts(Object? explanation) {
  if (explanation is! Map) return const [];
  if (asFiniteDouble(explanation['schema_version'])?.toInt() != 1) {
    return const [];
  }
  final rawFacts = explanation['facts'];
  if (rawFacts is! List) return const [];
  final out = <V4PillarFact>[];
  for (final rf in rawFacts) {
    if (rf is! Map) continue;
    final id = rf['id'] is String ? (rf['id'] as String).trim() : '';
    final label = rf['label'] is String ? rf['label'] as String : '';
    final valueDisplay = rf['value_display'] is String
        ? rf['value_display'] as String
        : '';
    if (id.isEmpty || label.trim().isEmpty || valueDisplay.trim().isEmpty) {
      continue;
    }
    final rawDetail = rf['detail'];
    final detail = rawDetail is String && rawDetail.trim().isNotEmpty
        ? rawDetail
        : null;
    out.add(
      V4PillarFact(
        id: id,
        label: label,
        valueDisplay: valueDisplay,
        detail: detail,
      ),
    );
  }
  return out;
}
