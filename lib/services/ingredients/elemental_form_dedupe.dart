// Elemental vs compound row dedupe — DISPLAY surface.
//
// Verified pipeline bug (dsld_id 315678, 'Magnesium Glycinate 400 mg'):
// the blob's `ingredients` carries TWO rows with canonical_id
// 'magnesium' — {'Magnesium', 60 mg} (elemental, the label-declared
// dose) and {'Magnesium Glycinate', 400 mg} (compound weight). Showing
// both renders two "magnesium" rows with two form-quality badges for
// one nutrient.
//
// Detection logic is the SAME brain as the nutrient-math dedupe in
// `lib/services/stack/stack_nutrient_aggregator.dart`
// (`_isElementalName` / `_compoundDuplicateRows`) and
// `lib/services/warnings/condition_gate.dart` (`_isElementalDoseName`):
// a row is "elemental" when its display name equals the canonical id
// after normalization, directly ('Magnesium') or after stripping a
// parenthetical ('Magnesium (elemental)', 'Magnesium (as oxide)').
// When a canonical group contains BOTH an elemental row and
// compound-named rows, the compound rows are duplicates of the
// elemental total. Groups that are all-elemental or all-compound
// (genuine multi-form labels like 'Magnesium (as oxide)' +
// 'Magnesium (as citrate)') are left untouched.
//
// Display twist (vs the math dedupe): instead of silently dropping the
// compound row, its name is folded into the surviving elemental row as
// form context — 'Magnesium (as Magnesium Glycinate)' — so the user
// still sees which form delivers the elemental dose.

import 'package:pharmaguide/services/ingredients/ingredient_canonicalizer.dart';

/// Resolve the label-facing display name of a raw ingredient row.
/// Mirrors the name-resolution chain used by `activeFromMap` in
/// `ingredients_helpers.dart` (display_label → standard_name → name →
/// raw_source_text).
String elementalDedupeDisplayName(Map<String, dynamic> row) {
  for (final field in const [
    'display_label',
    'standard_name',
    'name',
    'raw_source_text',
  ]) {
    final raw = row[field]?.toString().trim();
    if (raw != null && raw.isNotEmpty) return raw;
  }
  return '';
}

/// True when [displayName] is the bare elemental nutrient name for
/// [canonicalId]: equal after normalization, or equal after stripping a
/// parenthetical (e.g. 'Magnesium (elemental)' → 'Magnesium').
/// Deliberately conservative — anything that doesn't match exactly is
/// treated as a distinct (compound) form. Same rule as
/// `stack_nutrient_aggregator.dart` / `condition_gate.dart`.
bool isElementalIngredientName(String displayName, String canonicalId) {
  // applyAliases: false — this is a STRUCTURAL name match, not a synonym match.
  // With aliases on, `canonicalizeIngredientName('Vitamin B3')` folds to
  // 'niacin', so a generic "Vitamin B3" row would read as the bare elemental
  // total and drop every other niacin form from the sum (an under-count). The
  // hyphen/punctuation fold that fixes 'Vitamin-D3'/'5-HTP' is unaffected.
  final canonical = canonicalizeIngredientName(canonicalId, applyAliases: false);
  if (canonical.isEmpty) return false;
  if (canonicalizeIngredientName(displayName, applyAliases: false) == canonical) {
    return true;
  }
  final stripped = displayName.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  return canonicalizeIngredientName(stripped, applyAliases: false) == canonical;
}

/// Collapse elemental/compound duplicate rows for display.
///
/// When a canonical_id group contains a bare elemental row AND
/// compound-named rows, the compound rows are removed and the elemental
/// row (the true label dose) survives, with the compound name appended
/// as form context: 'Magnesium (as Magnesium Glycinate)'. The
/// elemental row keeps its own dose, badge fields, and tap payload —
/// only `display_label` is overridden, on a copied map (input maps are
/// never mutated).
///
/// Rows without a usable `canonical_id`, single-row groups,
/// all-elemental groups, and all-compound groups (legit multi-form
/// labels) pass through unchanged. Order is preserved.
List<Map<String, dynamic>> dedupeElementalCompoundRows(
  List<Map<String, dynamic>> ingredients,
) {
  if (ingredients.length < 2) return ingredients;

  final byCanonical = <String, List<int>>{};
  for (var i = 0; i < ingredients.length; i++) {
    final canonical = canonicalizeIngredientName(
      ingredients[i]['canonical_id']?.toString() ?? '',
    );
    if (canonical.isEmpty) continue;
    byCanonical.putIfAbsent(canonical, () => []).add(i);
  }

  final dropped = <int>{};
  // First elemental index per group → joined compound names for the
  // "(as ...)" suffix.
  final formContext = <int, String>{};

  for (final entry in byCanonical.entries) {
    final indexes = entry.value;
    if (indexes.length < 2) continue;

    final elementalIndexes = <int>[];
    final compoundIndexes = <int>[];
    for (final i in indexes) {
      final name = elementalDedupeDisplayName(ingredients[i]);
      if (isElementalIngredientName(name, entry.key)) {
        elementalIndexes.add(i);
      } else {
        compoundIndexes.add(i);
      }
    }
    // No bare elemental sibling (multi-form label) or nothing compound:
    // leave the group alone.
    if (elementalIndexes.isEmpty || compoundIndexes.isEmpty) continue;

    final compoundNames = <String>[];
    for (final i in compoundIndexes) {
      dropped.add(i);
      final name = elementalDedupeDisplayName(ingredients[i]);
      if (name.isNotEmpty) compoundNames.add(name);
    }
    if (compoundNames.isNotEmpty) {
      formContext[elementalIndexes.first] = compoundNames.join(', ');
    }
  }

  if (dropped.isEmpty) return ingredients;

  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < ingredients.length; i++) {
    if (dropped.contains(i)) continue;
    final context = formContext[i];
    if (context == null) {
      out.add(ingredients[i]);
      continue;
    }
    final name = elementalDedupeDisplayName(ingredients[i]);
    // Already carries a parenthetical (e.g. 'Magnesium (elemental)') —
    // don't stack a second one.
    if (name.contains('(')) {
      out.add(ingredients[i]);
      continue;
    }
    out.add(<String, dynamic>{
      ...ingredients[i],
      'display_label': '$name (as $context)',
    });
  }
  return out;
}
