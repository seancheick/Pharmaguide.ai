import 'dart:convert';

import 'package:pharmaguide/data/database/core_database.dart';

const Set<String> _structuredFingerprintKeys = <String>{
  'nutrients',
  'herbs',
  'categories',
  'pharmacological_flags',
};

/// Fold any raw ingredient string into the catalog's canonical-id form.
///
/// This is the ONE canonicalizer for the catalog ingredient namespace. Any
/// code that needs to compare a free-text ingredient name against catalog
/// ids must fold it through here rather than writing its own — two
/// canonicalizers is how a join silently stops matching.
String? normalizeCanonicalId(Object? value) => _normalizeCanonicalId(value);

String? _normalizeCanonicalId(Object? value) {
  if (value == null) return null;
  final raw = value.toString().trim().toLowerCase();
  if (raw.isEmpty) return null;
  if (_structuredFingerprintKeys.contains(raw)) return null;

  final normalized = raw
      .replaceAll('&', ' and ')
      .replaceAll("'", '')
      .replaceAll('’', '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (normalized.isEmpty) return null;
  if (_structuredFingerprintKeys.contains(normalized)) return null;
  return normalized;
}

void _addCanonicalId(Set<String> ids, Object? value) {
  final normalized = _normalizeCanonicalId(value);
  if (normalized != null) ids.add(normalized);
}

/// Extract canonical ingredient IDs from any catalog JSON carrier.
///
/// Supported shapes:
/// - JSON list: `["potassium", "magnesium"]`
/// - legacy keyed map: `{"potassium": {"amount": 99}}`
/// - structured fingerprint:
///   `{"nutrients": {"potassium": {}}, "herbs": ["ashwagandha"]}`
///
/// Structural keys are never returned as ingredient IDs.
List<String> canonicalIdsFromJsonString(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(raw);
    return canonicalIdsFromDecoded(decoded);
  } on FormatException {
    return const <String>[];
  }
}

List<String> canonicalIdsFromDecoded(Object? decoded) {
  final ids = <String>{};

  if (decoded is List) {
    for (final item in decoded) {
      _addCanonicalId(ids, item);
    }
    return ids.toList(growable: false);
  }

  if (decoded is Map) {
    final isStructured = decoded.keys
        .map((key) => key.toString())
        .any(_structuredFingerprintKeys.contains);

    if (isStructured) {
      final nutrients = decoded['nutrients'];
      if (nutrients is Map) {
        for (final key in nutrients.keys) {
          _addCanonicalId(ids, key);
        }
      }

      final herbs = decoded['herbs'];
      if (herbs is List) {
        for (final herb in herbs) {
          _addCanonicalId(ids, herb);
        }
      }
      return ids.toList(growable: false);
    }

    for (final key in decoded.keys) {
      _addCanonicalId(ids, key);
    }
  }

  return ids.toList(growable: false);
}

/// Extract canonical IDs from the product detail blob active ingredients.
List<String> canonicalIdsFromDetailBlob(Map<String, dynamic>? detailBlob) {
  if (detailBlob == null) return const <String>[];
  final ids = <String>{};

  void scanIngredients(Object? rawIngredients) {
    if (rawIngredients is! List) return;
    for (final item in rawIngredients) {
      if (item is! Map) continue;
      _addCanonicalId(ids, item['canonical_id']);
    }
  }

  scanIngredients(detailBlob['ingredients']);

  final ingredientQualityData = detailBlob['ingredient_quality_data'];
  if (ingredientQualityData is Map) {
    scanIngredients(ingredientQualityData['ingredients']);
  }

  return ids.toList(growable: false);
}

/// Marker canonical IDs that a product's active ingredients *deliver* — the
/// pipeline's `delivers_markers` payload (e.g. a turmeric source ingredient
/// delivers the `curcumin` marker). Each entry carries `marker_canonical_id`.
///
/// EVIDENCE ROUTING ONLY. Markers bridge a source botanical to the bioactive
/// compound that research pairs are keyed on, but are deliberately kept OUT of
/// the interaction/safety path so a trace botanical cannot manufacture a
/// marker-keyed warning. Consumed via [researchCanonicalIdsForProduct].
List<String> markerCanonicalIdsFromDetailBlob(
  Map<String, dynamic>? detailBlob,
) {
  if (detailBlob == null) return const <String>[];
  final ids = <String>{};

  void scanIngredients(Object? rawIngredients) {
    if (rawIngredients is! List) return;
    for (final item in rawIngredients) {
      if (item is! Map) continue;
      final markers = item['delivers_markers'];
      if (markers is! List) continue;
      for (final marker in markers) {
        if (marker is Map) _addCanonicalId(ids, marker['marker_canonical_id']);
      }
    }
  }

  scanIngredients(detailBlob['ingredients']);

  final ingredientQualityData = detailBlob['ingredient_quality_data'];
  if (ingredientQualityData is Map) {
    scanIngredients(ingredientQualityData['ingredients']);
  }

  return ids.toList(growable: false);
}

/// Canonical IDs available from a product row plus, when present, its detail blob.
///
/// Product-row sources are intentionally ordered first because Quick Check must
/// work from the bundled catalog without a network detail-blob fetch.
List<String> canonicalIdsForProduct(
  ProductsCoreData product, {
  Map<String, dynamic>? detailBlob,
}) {
  final ids = <String>{};
  ids.addAll(canonicalIdsFromJsonString(product.keyIngredientTags));
  ids.addAll(canonicalIdsFromJsonString(product.ingredientFingerprint));
  ids.addAll(canonicalIdsFromDetailBlob(detailBlob));
  return ids.toList(growable: false);
}

/// Canonical IDs for **research/evidence routing** on the product-detail
/// surface: everything from [canonicalIdsForProduct] plus the bioactive markers
/// the actives deliver ([markerCanonicalIdsFromDetailBlob]).
///
/// Markers widen evidence reach (a turmeric product also surfaces curcumin
/// research) without touching the interaction/safety path, which keeps using
/// [canonicalIdsForProduct] (source ids only). `delivers_markers` lives in the
/// online detail blob, so this collapses to source ids offline.
List<String> researchCanonicalIdsForProduct(
  ProductsCoreData product, {
  Map<String, dynamic>? detailBlob,
}) {
  return <String>{
    ...canonicalIdsForProduct(product, detailBlob: detailBlob),
    ...markerCanonicalIdsFromDetailBlob(detailBlob),
  }.toList(growable: false);
}
