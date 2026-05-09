/// Free-from claim matcher (Phase 8 follow-up).
///
/// Pairs the user's profile allergens against the pipeline's three
/// boolean free-from columns on `products_core`:
///
///   `is_gluten_free`  ↔  ALLERGEN_WHEAT / BARLEY / RYE / OATS
///   `is_dairy_free`   ↔  ALLERGEN_MILK
///   `is_soy_free`     ↔  ALLERGEN_SOY
///
/// Where the existing [matchAllergens] surfaces *negative* signals
/// ("contains wheat" → warn), this matcher surfaces the *affirmative*
/// counterpart ("certified gluten-free" → reassure) for the same
/// allergen concerns. Together they give the user a complete picture
/// of how the product relates to their selected sensitivities.
///
/// Pipeline note: only three of the 13 user-side allergen chips have
/// corresponding free-from columns today (gluten / dairy / soy). The
/// other ten (eggs, fish, shellfish, tree nuts, peanuts, sesame,
/// sulfites, celery, mustard, lupin) have no free-from boolean to
/// match against — when the pipeline ships more, extend
/// [_concernMappings] below.
library;

/// Status of a free-from claim against a single user concern.
///
/// Mirrors the tri-state nullable INT in `products_core`:
///   1     → [certified]   — explicit free-from claim verified
///   0     → [notClaimed]  — checked, no claim made (we skip this status
///                            when rendering — it's just absence)
///   null  → [unknown]     — pipeline never had data
enum FreeFromStatus {
  /// Product carries a verified free-from claim matching this concern.
  /// Pipeline emitted `1` for the corresponding `is_*_free` column.
  certified,

  /// Product was inspected and explicitly marked NOT free-from
  /// (`is_*_free = 0`). Treated as data presence, not a warning —
  /// callers may choose to ignore.
  notClaimed,

  /// Pipeline didn't capture any data for this claim (`is_*_free = null`).
  unknown,
}

/// One free-from claim's outcome for the user.
///
/// Generated only when the user actually has the allergen in their
/// profile — so the resulting list is always sized to "claims relevant
/// to this user."
class FreeFromClaim {
  /// User-facing label for the claim (e.g. "Gluten-free", "Dairy-free").
  /// Hyphenated to match the existing hero chip vocabulary.
  final String label;

  /// Stable concern key (e.g. `gluten`, `dairy`, `soy`) — used for
  /// telemetry, debugging, and conflict-pairing with [matchAllergens]
  /// output. Lowercase, no spaces.
  final String concern;

  /// Resolved status from the product's free-from column.
  final FreeFromStatus status;

  const FreeFromClaim({
    required this.label,
    required this.concern,
    required this.status,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreeFromClaim &&
          label == other.label &&
          concern == other.concern &&
          status == other.status;

  @override
  int get hashCode => Object.hash(label, concern, status);

  @override
  String toString() => 'FreeFromClaim($label, $concern, $status)';
}

/// Internal mapping: for a given user concern, which canonical allergen
/// IDs trigger it, what the user-facing label is, and which Drift flag
/// drives the status. Order is surface-render order — gluten first
/// because it's the most-selected concern in our cohort.
class _ConcernMapping {
  final String concern;
  final String label;
  final Set<String> allergenIds;

  const _ConcernMapping({
    required this.concern,
    required this.label,
    required this.allergenIds,
  });
}

const List<_ConcernMapping> _concernMappings = [
  _ConcernMapping(
    concern: 'gluten',
    label: 'Gluten-free',
    allergenIds: {
      'ALLERGEN_WHEAT',
      'ALLERGEN_BARLEY',
      'ALLERGEN_RYE',
      'ALLERGEN_OATS',
    },
  ),
  _ConcernMapping(
    concern: 'dairy',
    label: 'Dairy-free',
    allergenIds: {'ALLERGEN_MILK'},
  ),
  _ConcernMapping(
    concern: 'soy',
    label: 'Soy-free',
    allergenIds: {'ALLERGEN_SOY'},
  ),
];

/// Compute the user-relevant free-from claims for a product.
///
/// Returns a list of [FreeFromClaim] in concern order (gluten, dairy,
/// soy), one entry per user concern that has a corresponding free-from
/// column. Concerns the user hasn't selected are omitted entirely —
/// the result is a personalized view.
///
/// Pass the three Drift `int?` flags directly so callers can use this
/// without depending on the full `ProductsCoreData` type (helps testing
/// and keeps the helper feature-folder local).
///
/// Returns `const []` when [userAllergenIds] is empty.
List<FreeFromClaim> matchFreeFromClaims({
  required Set<String> userAllergenIds,
  required int? isGlutenFree,
  required int? isDairyFree,
  required int? isSoyFree,
}) {
  if (userAllergenIds.isEmpty) return const [];
  final claims = <FreeFromClaim>[];
  for (final mapping in _concernMappings) {
    if (!mapping.allergenIds.any(userAllergenIds.contains)) continue;
    final flag = switch (mapping.concern) {
      'gluten' => isGlutenFree,
      'dairy' => isDairyFree,
      'soy' => isSoyFree,
      _ => null,
    };
    claims.add(
      FreeFromClaim(
        label: mapping.label,
        concern: mapping.concern,
        status: _statusFromFlag(flag),
      ),
    );
  }
  return claims;
}

FreeFromStatus _statusFromFlag(int? flag) {
  return switch (flag) {
    1 => FreeFromStatus.certified,
    0 => FreeFromStatus.notClaimed,
    _ => FreeFromStatus.unknown,
  };
}

/// Detect label disagreements between [matchAllergens]'s output and
/// the free-from claims. A conflict is when the matcher reports a
/// `contains` row for an allergen group AND the corresponding
/// `is_*_free` flag is `1` — the pipeline contradicts itself, and the
/// user deserves to know rather than have us pick a side.
///
/// Returns the list of concern keys that are in conflict (e.g.
/// `['gluten']`). Empty when there are no conflicts. Caller renders
/// a "label disagreement — please read the label" hint when non-empty.
///
/// [matchedAllergenIds] should be the set of `MatchedAllergen.id`
/// values whose `presenceType == 'contains'`. Higher-tier presence
/// types (`may_contain`, `manufactured_in_facility`) are intentionally
/// ignored — the pipeline can legitimately mark a product gluten-free
/// while disclosing facility cross-contamination.
List<String> findFreeFromConflicts({
  required Set<String> matchedContainsAllergenIds,
  required int? isGlutenFree,
  required int? isDairyFree,
  required int? isSoyFree,
}) {
  if (matchedContainsAllergenIds.isEmpty) return const [];
  final conflicts = <String>[];
  for (final mapping in _concernMappings) {
    final flag = switch (mapping.concern) {
      'gluten' => isGlutenFree,
      'dairy' => isDairyFree,
      'soy' => isSoyFree,
      _ => null,
    };
    if (flag != 1) continue;
    if (mapping.allergenIds.any(matchedContainsAllergenIds.contains)) {
      conflicts.add(mapping.concern);
    }
  }
  return conflicts;
}
