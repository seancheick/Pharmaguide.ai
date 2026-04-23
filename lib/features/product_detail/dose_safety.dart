/// Per-ingredient dose-vs-UL safety helpers.
///
/// The detail blob carries per-ingredient UL data emitted by the
/// pipeline (`ul_19_30`, `highest_ul`). These helpers keep the
/// comparison logic pure so it can be unit-tested without a widget
/// tree.
///
/// Policy — matches the safety hierarchy in the Flutter handoff §0:
/// UL exceedance outranks dose-quality labels. A product whose dose
/// is above the UL must never render a positive badge like "Well
/// dosed" no matter how good the bioavailability score is
/// (FLTR-11 — the Vitamin A 25,000 IU regression).

library;

/// Returns true when the ingredient's disclosed dose exceeds the
/// upper-limit threshold carried by the ingredient map.
///
/// Lookup order, honoring the pipeline contract:
///   1. `ul_19_30` — default adult UL in the current blob shape.
///   2. `highest_ul` — anonymous-safe fallback (worst-case across
///      demographics). Conservative: a true exceedance anywhere
///      fires the badge.
///
/// Returns false when any input is missing or non-positive so
/// incomplete data never produces a false alarm.
bool ingredientExceedsUl(Map<String, dynamic> ingredient) {
  final amount = _asDouble(ingredient['amount']);
  if (amount == null || amount <= 0) return false;

  final ul = _asDouble(ingredient['ul_19_30']) ??
      _asDouble(ingredient['highest_ul']);
  if (ul == null || ul <= 0) return false;

  return amount > ul;
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v.isFinite ? v : null;
  if (v is int) return v.toDouble();
  if (v is String) {
    final parsed = double.tryParse(v.trim());
    return (parsed != null && parsed.isFinite) ? parsed : null;
  }
  return null;
}
