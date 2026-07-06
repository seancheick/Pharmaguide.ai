// Ingredient-name canonicalization — shared across the warning gate, blend
// grouping, and stack dose math.
//
// Extracted from the retired app-owned condition-threshold table so this pure
// string utility can be shared by emitted warning gates, stack dose math, and
// ingredient grouping. No behavior change — the function and its alias map
// moved verbatim.

/// Canonicalize a free-text ingredient name to the lowercase +
/// underscore-joined form used by warning and stack-dose matching.
///
/// `'Vitamin D'`                       → `'vitamin_d'`
/// `'Magnesium Glycinate'`             → `'magnesium_glycinate'`
/// `'  Iron '`                         → `'iron'`
/// `'Vitamin-D3'`                      → `'vitamin_d3'`
/// `'Cinnamon Bark Extract, Dried'`    → `'cinnamon_bark_extract_dried'`
/// `'Vitamin C (as ascorbic acid)'`    → `'vitamin_c_as_ascorbic_acid'`
///
/// **T16.2e (2026-04-30) — punctuation strip:** Sean's PureLean live
/// walkthrough surfaced "Cinnamon Bark Extract, Dried" leaking through
/// the §7 condition_summary surface even after we added cinnamon_*
/// positive entries. Pre-T16.2e the canonicalizer only collapsed
/// whitespace and hyphens, so the comma+space survived as literal
/// `,_dried` characters in the key. Pipeline names commonly carry
/// trailing descriptor punctuation (`", Dried"`, `" (USP)"`,
/// `", powder."`) that the table side never matches. Strip the lot at
/// the boundary so the table keys can stay clean.
String canonicalizeIngredientName(String raw) {
  final trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  // Whitespace, hyphens, AND punctuation runs all collapse to a single
  // underscore. Trailing/leading underscores are stripped after
  // collapsing so `'(USP)'` → `'usp'`, not `'_usp_'`.
  final collapsed = trimmed.replaceAll(RegExp(r'[\s\-,.;:()\[\]/]+'), '_');
  // Strip any leading/trailing underscores left behind by punctuation
  // at the edges.
  final canonical = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
  return _ingredientCanonicalAliases[canonical] ?? canonical;
}

const Map<String, String> _ingredientCanonicalAliases = {
  // DSLD and pipeline blobs use all of these for niacin depending on
  // source row. The threshold table intentionally keys the clinical
  // rule once as `niacin`, so aliases must collapse before dose lookup.
  'vitamin_b_3': 'niacin',
  'vitamin_b3': 'niacin',
  'vitamin_b_3_niacin': 'niacin',
  'vitamin_b3_niacin': 'niacin',
};
