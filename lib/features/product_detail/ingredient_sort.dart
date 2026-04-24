/// FLTR-9 — present active ingredients in a deterministic order so
/// the list reads predictably across products.
///
/// Two buckets:
///   1. disclosed — ingredients with a positive numeric `quantity`
///   2. undisclosed — no dose, zero, null, or non-numeric quantity
///
/// Order is preserved WITHIN each bucket. The pipeline emits
/// ingredients in supplement-facts label order, which is already
/// meaningful (the order declared on the bottle) and shouldn't be
/// re-shuffled by the UI without a good reason.
///
/// No cross-unit dose comparison is attempted. A product mixing
/// IU / mg / mcg would require unit-aware normalization to sort
/// by magnitude, and any naive numeric sort would be misleading
/// (25,000 IU of Vitamin A is not "greater than" 10 mg of Zinc).
/// Unit-aware sorting is Release C / pipeline scope — kept out of
/// FLTR-9 on purpose.

library;

/// Returns a new list with disclosed-dose ingredients first,
/// then undisclosed. Input is not mutated.
List<Map<String, dynamic>> sortActivesForDisplay(
  Iterable<Map<String, dynamic>> ingredients,
) {
  final disclosed = <Map<String, dynamic>>[];
  final undisclosed = <Map<String, dynamic>>[];
  for (final ing in ingredients) {
    final qty = ing['quantity'];
    final isDisclosed = qty is num && qty > 0;
    (isDisclosed ? disclosed : undisclosed).add(ing);
  }
  return <Map<String, dynamic>>[...disclosed, ...undisclosed];
}
