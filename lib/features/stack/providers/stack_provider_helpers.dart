// Library-internal helpers shared by the split stack provider files
// (active_stack_provider.dart, stack_safety_providers.dart,
// synergy_report_provider.dart). Not exported from stack_providers.dart —
// importers should use the public providers.
//
// The names are intentionally prefixed with `stackInternal*` so a
// grep-for-usage across the codebase makes the internal surface obvious.

import 'dart:convert';

import 'package:pharmaguide/core/utils/product_canonical_ids.dart'
    as canonical_ids;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';

/// Wrapper pairing a stack entry with its core product row. Used by the
/// safety / synergy providers so we don't hit the core DB twice per check.
class HydratedSupplement {
  const HydratedSupplement({required this.entry, required this.product});
  final UserStacksLocalData entry;
  final ProductsCoreData product;
}

/// Extract canonical ingredient ids for interaction matching.
///
/// Delegates to the shared catalog parser so Stack, Quick Check, Product
/// Detail, scanner results, and legacy stack rows agree on ID semantics.
List<String> canonicalIdsForProduct(ProductsCoreData product) {
  return canonical_ids.canonicalIdsForProduct(product);
}

/// Extract canonical ingredient tags from a product's `key_ingredient_tags`
/// column. Returns a Set for O(1) containment checks during timing evaluation.
///
/// Example: `["magnesium", "vitamin_d", "zinc"]` → `{"magnesium", "vitamin_d", "zinc"}`
///
/// Falls back to canonical IDs recoverable from `ingredient_fingerprint`, so
/// older product rows still get timing advice without a local parser fork.
Set<String> ingredientTagsForProduct(ProductsCoreData product) {
  return canonical_ids.canonicalIdsForProduct(product).toSet();
}

/// Decode a JSON fingerprint column to a map. Returns an empty map on
/// null, empty, malformed, or non-map inputs.
Map<String, dynamic> parseFingerprint(String? raw) {
  if (raw == null || raw.isEmpty) return const <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return const <String, dynamic>{};
  }
  return const <String, dynamic>{};
}

/// Stable key for a heuristic interaction between two agents — ignores
/// ordering so we dedupe A×B and B×A to one warning per category.
String symmetricKey(String a, String b, String ruleId) {
  // Keep the rule prefix (`STACK_STIM_SED`, `STACK_SED_STIM`,
  // `STACK_BLOOD_THINNER_*`, ...) but strip the trailing numeric index
  // so A→B and B→A collapse to the same bucket.
  final prefix = ruleId.replaceAll(RegExp(r'_\d+$'), '');
  final pair = (a.compareTo(b) <= 0) ? '$a|$b' : '$b|$a';
  return '$prefix#$pair';
}
