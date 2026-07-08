// Canonical dose-unit normalization + simple-mass conversion.
//
// Single source of truth for the unit-spelling and g/mg/mcg math that used to
// be copy-pasted (and quietly drifting) across six stack/dose/warning files:
// `stack_dose_summer`, `stack_ul_checker`, `stack_nutrient_aggregator`,
// `services/health/dose_safety`, `services/warnings/condition_gate`, and
// `depletion_checker`. Centralising kills the drift class an audit found live:
// a Unicode micro-sign mismatch (µ U+00B5 vs μ U+03BC), an ASCII "ug" alias
// present in only one file, and inconsistent "I.U." folding.
//
// IU / RAE / DFE / NE are deliberately NOT converted here — those are
// form-dependent and owned by the pipeline's `unit_conversions.json`. The app
// declines (returns null) rather than guess a form-dependent factor.

/// Normalize a raw unit string to a canonical token.
///
/// Lower-cases, trims, folds every micro-gram spelling — `µg` (U+00B5 micro
/// sign), `μg` (U+03BC Greek mu), and ASCII `ug` — to `mcg`, folds
/// `i.u.` / `international unit(s)` to `iu`, turns `_` and `-` into spaces
/// (so `alpha-tocopherol` matches `alpha tocopherol`), and collapses
/// whitespace. Idempotent: normalizing an already-normalized token is a no-op.
String normalizeDoseUnit(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll('µg', 'mcg') // U+00B5 MICRO SIGN
      .replaceAll('μg', 'mcg') // U+03BC GREEK SMALL LETTER MU
      // Underscore/hyphen → space FIRST, so hyphenated/underscored IU spellings
      // ("international-units") fold to "iu" and normalization stays idempotent.
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAll('i.u.', 'iu')
      .replaceAll('international units', 'iu')
      .replaceAll('international unit', 'iu')
      .replaceAll(RegExp(r'\bug\b'), 'mcg') // ASCII "ug" → mcg (whole token)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Grams per one unit of [unit] for the simple mass family (g / mg / mcg and
/// their spellings), or `null` when [unit] is not a simple mass unit
/// (e.g. `iu`, `mcg rae`, `mcg dfe` — form-dependent, never guessed here).
///
/// Accepts either a raw or already-normalized unit; it normalizes internally.
double? massGramsFactor(String unit) {
  return switch (normalizeDoseUnit(unit)) {
    'g' || 'gram' || 'grams' || 'gram(s)' => 1.0,
    'mg' => 0.001,
    'mcg' || 'microgram' || 'micrograms' => 0.000001,
    _ => null,
  };
}

/// Convert [amount] from [from] to [to] within the simple mass family.
///
/// Returns [amount] unchanged when the two units normalize equal (so `ug` and
/// `mcg` reconcile), the factor-scaled value for a valid g/mg/mcg pair, or
/// `null` when either side is empty or not a simple mass unit. Callers decide
/// whether a `null` means "decline the comparison" or "assume same unit" — this
/// primitive never guesses a form-dependent (IU/RAE/DFE) conversion.
double? amountInMass(double amount, {required String from, required String to}) {
  final normalizedFrom = normalizeDoseUnit(from);
  final normalizedTo = normalizeDoseUnit(to);
  if (normalizedFrom.isEmpty || normalizedTo.isEmpty) return null;
  if (normalizedFrom == normalizedTo) return amount;

  final fromGrams = massGramsFactor(normalizedFrom);
  final toGrams = massGramsFactor(normalizedTo);
  if (fromGrams == null || toGrams == null) return null;
  return amount * fromGrams / toGrams;
}
