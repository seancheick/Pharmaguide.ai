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

/// FLTR-6 — collapse duplicate inactive ingredients.
///
/// Despite the handoff's claim that the blob ships with unique
/// inactives, sampling the real blobs shows duplicates in
/// practice (e.g. "cellulose" appears twice in dsld 299056
/// GlutenAssure Multivitamin and dsld 287463 PS Plus; "ethyl
/// vanillin" twice in dsld 302654). Dedupe at the UI boundary
/// so the user sees one chip per distinct excipient.
///
/// Match key is the normalized (trimmed + lowercased) first
/// non-empty value of `name`, `standard_name`, or
/// `raw_source_text`. First occurrence wins — preserves the
/// pipeline's declared order.
List<Map<String, dynamic>> dedupeInactivesForDisplay(
  Iterable<Map<String, dynamic>> inactives,
) {
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final ing in inactives) {
    final raw = (ing['name'] ??
            ing['standard_name'] ??
            ing['raw_source_text'])
        ?.toString();
    final key = raw?.trim().toLowerCase() ?? '';
    if (key.isEmpty) continue;
    if (seen.add(key)) out.add(ing);
  }
  return out;
}
