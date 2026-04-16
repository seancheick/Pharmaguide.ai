// Library-internal helpers shared by the split stack provider files
// (active_stack_provider.dart, stack_safety_providers.dart,
// synergy_report_provider.dart). Not exported from stack_providers.dart —
// importers should use the public providers.
//
// The names are intentionally prefixed with `stackInternal*` so a
// grep-for-usage across the codebase makes the internal surface obvious.

import 'dart:convert';

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
/// Primary source: `key_ingredient_tags` column — a JSON array of
/// canonical IDs like `["iron", "calcium", "vitamin_d"]` that the
/// pipeline writes from IQM parent keys.
///
/// Secondary source: `herbs` list inside `ingredient_fingerprint`
/// (for herbal products whose canonical IDs live there).
///
/// Previous implementation read fingerprint top-level map keys which
/// always returned `["nutrients", "herbs", "categories", "pharmacological_flags"]`
/// — structural keys, NOT ingredient IDs. This caused all curated
/// interaction lookups via `lookupByCanonicalId` to silently return
/// nothing for every product. Fixed 2026-04-14.
List<String> canonicalIdsForProduct(ProductsCoreData product) {
  final ids = <String>{};

  // Primary: key_ingredient_tags (most accurate).
  final rawTags = product.keyIngredientTags;
  if (rawTags != null && rawTags.isNotEmpty) {
    try {
      final decoded = jsonDecode(rawTags);
      if (decoded is List) {
        for (final tag in decoded) {
          final s = tag.toString().toLowerCase().trim();
          if (s.isNotEmpty) ids.add(s);
        }
      }
    } on FormatException {
      // Fall through to fingerprint.
    }
  }

  // Secondary: herbs list from ingredient_fingerprint.
  final rawFp = product.ingredientFingerprint;
  if (rawFp != null && rawFp.isNotEmpty) {
    try {
      final decoded = jsonDecode(rawFp);
      if (decoded is Map) {
        final herbs = decoded['herbs'];
        if (herbs is List) {
          for (final h in herbs) {
            final s = h.toString().toLowerCase().trim();
            if (s.isNotEmpty) ids.add(s);
          }
        }
      }
    } on FormatException {
      // Best-effort.
    }
  }

  return ids.toList(growable: false);
}

/// Extract canonical ingredient tags from a product's `key_ingredient_tags`
/// column. Returns a Set for O(1) containment checks during timing evaluation.
///
/// Example: `["magnesium", "vitamin_d", "zinc"]` → `{"magnesium", "vitamin_d", "zinc"}`
///
/// Falls back to the `herbs` list in `ingredient_fingerprint` if
/// `key_ingredient_tags` is empty, so herbal products still get timing advice.
Set<String> ingredientTagsForProduct(ProductsCoreData product) {
  final tags = <String>{};

  // Primary source: key_ingredient_tags column (most accurate).
  final rawTags = product.keyIngredientTags;
  if (rawTags != null && rawTags.isNotEmpty) {
    try {
      final decoded = jsonDecode(rawTags);
      if (decoded is List) {
        for (final tag in decoded) {
          final s = tag.toString().toLowerCase().trim();
          if (s.isNotEmpty) tags.add(s);
        }
      }
    } on FormatException {
      // Silently fall through to fingerprint fallback.
    }
  }

  // Secondary source: herbs list from ingredient_fingerprint.
  final rawFp = product.ingredientFingerprint;
  if (rawFp != null && rawFp.isNotEmpty) {
    try {
      final decoded = jsonDecode(rawFp);
      if (decoded is Map) {
        final herbs = decoded['herbs'];
        if (herbs is List) {
          for (final h in herbs) {
            final s = h.toString().toLowerCase().trim();
            if (s.isNotEmpty) tags.add(s);
          }
        }
      }
    } on FormatException {
      // Best-effort.
    }
  }

  return tags;
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
