// Ingredient-category vocab loader.
//
// Pipeline contract (v1.0.0, schema in pipeline repo
// `scripts/data/ingredient_category_vocab.json`): 17 canonical singular
// ingredient-category IDs covering the IQM parent buckets (vitamin,
// mineral, herb, botanical, antioxidant, fatty_acid, amino_acid,
// probiotic, bacteria, protein, fiber, enzyme, functional_food) plus
// non-IQM rows (delivery, additive, inactive, other).
//
// Distinct from `iqm_category_vocab.dart` (which carries the LOCKED
// PLURAL IQM-parent-level vocab used by integrity gates and the catalog
// DB). This vocab is line-level — what individual ingredient rows
// canonicalize to during enrichment.
//
// Consumed by the ingredient drawer / detail panel to label rows with
// the canonical category short_name and look up the category description.
//
// Loaded once at first call to `loadIngredientCategoryVocab()`; cached
// process-lifetime.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class IngredientCategoryEntry {
  final String id;
  final String shortName;
  final String description;
  final List<String> aliases;
  final String? iqmParentCategory;

  const IngredientCategoryEntry({
    required this.id,
    required this.shortName,
    required this.description,
    required this.aliases,
    required this.iqmParentCategory,
  });

  factory IngredientCategoryEntry.fromJson(Map<String, dynamic> json) {
    final aliasesRaw = json['aliases'];
    return IngredientCategoryEntry(
      id: json['id']?.toString() ?? '',
      shortName: json['short_name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      aliases: aliasesRaw is List
          ? aliasesRaw.map((a) => a.toString()).toList()
          : const [],
      iqmParentCategory: json['iqm_parent_category']?.toString(),
    );
  }
}

Map<String, IngredientCategoryEntry>? _cache;

Future<Map<String, IngredientCategoryEntry>>
loadIngredientCategoryVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/ingredient_category_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['ingredient_categories'] as List?) ?? const [];

  final byId = <String, IngredientCategoryEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final c = IngredientCategoryEntry.fromJson(entry);
    if (c.id.isEmpty) continue;
    byId[c.id] = c;
  }

  _cache = byId;
  return byId;
}

void debugSetIngredientCategoryVocabForTesting(
  Map<String, IngredientCategoryEntry>? value,
) {
  _cache = value;
}
