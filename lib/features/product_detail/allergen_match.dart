/// Personalized allergen matcher (Phase 8).
///
/// Pure exact-id matching against the structured `detail_blob.allergens[]`
/// emitted by the pipeline (Phase 7B / `build_structured_allergens` in
/// `scripts/build_final_db.py`). No substring matching — every allergen the
/// pipeline can flag has a canonical ID listed in `scripts/data/allergens.json`,
/// and the user's profile stores those exact IDs.
///
/// The result is sorted by `presence_type` priority so the most actionable
/// rows render first:
///   contains → may_contain → manufactured_in_facility
/// Within each presence tier, severity (high → moderate → low) breaks ties.
library;

class MatchedAllergen {
  /// Canonical allergen ID (e.g. `ALLERGEN_SOY`). Stable across pipeline
  /// versions; the user profile stores the same string.
  final String id;

  /// Human-readable display label from the pipeline (e.g. "Soy & Soy Lecithin").
  final String displayName;

  /// One of: `contains`, `may_contain`, `manufactured_in_facility`.
  /// Drives the UI severity treatment — `contains` is a hard flag,
  /// `may_contain` is amber caution, the facility tier is informational.
  final String presenceType;

  /// One of: `high`, `moderate`, `low`. Pipeline-supplied per
  /// `allergens.json`. Used for tie-breaking and severity styling.
  final String severityLevel;

  /// Optional source quote from the label (e.g. "Contains: Soy"). May be
  /// empty when the pipeline didn't capture verbatim evidence.
  final String? evidence;

  const MatchedAllergen({
    required this.id,
    required this.displayName,
    required this.presenceType,
    required this.severityLevel,
    this.evidence,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchedAllergen &&
          id == other.id &&
          displayName == other.displayName &&
          presenceType == other.presenceType &&
          severityLevel == other.severityLevel &&
          evidence == other.evidence;

  @override
  int get hashCode =>
      Object.hash(id, displayName, presenceType, severityLevel, evidence);
}

/// Match the user's profile allergens against the product's structured
/// allergen array.
///
/// Returns matches sorted by presence priority then severity. Empty when
/// the user has no allergens or the product has no structured allergens.
///
/// Defensive against malformed entries (non-Map elements, missing
/// `allergen_id`) — those are skipped, not thrown.
List<MatchedAllergen> matchAllergens(
  List<String> userAllergenIds,
  List<dynamic>? structuredAllergens,
) {
  if (userAllergenIds.isEmpty || structuredAllergens == null) {
    return const [];
  }
  final userSet = userAllergenIds.toSet();
  final matches = <MatchedAllergen>[];
  for (final entry in structuredAllergens) {
    if (entry is! Map) continue;
    final id = entry['allergen_id']?.toString() ?? '';
    if (id.isEmpty || !userSet.contains(id)) continue;
    final evidence = entry['evidence']?.toString();
    matches.add(
      MatchedAllergen(
        id: id,
        displayName: entry['display_name']?.toString() ?? id,
        presenceType: entry['presence_type']?.toString() ?? 'contains',
        severityLevel: entry['severity_level']?.toString() ?? 'moderate',
        evidence: (evidence == null || evidence.isEmpty) ? null : evidence,
      ),
    );
  }
  matches.sort((a, b) {
    final p = _presencePriority(a.presenceType)
        .compareTo(_presencePriority(b.presenceType));
    if (p != 0) return p;
    return _severityPriority(a.severityLevel)
        .compareTo(_severityPriority(b.severityLevel));
  });
  return matches;
}

int _presencePriority(String presenceType) {
  switch (presenceType) {
    case 'contains':
      return 0;
    case 'may_contain':
      return 1;
    case 'manufactured_in_facility':
      return 2;
    default:
      return 99;
  }
}

int _severityPriority(String severity) {
  switch (severity) {
    case 'high':
      return 0;
    case 'moderate':
      return 1;
    case 'low':
      return 2;
    default:
      return 99;
  }
}
