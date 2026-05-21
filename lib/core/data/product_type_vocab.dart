// Product-type vocab loader.
//
// Pipeline contract (v1.0.0, schema in pipeline repo
// `scripts/data/product_type_vocab.json`): 20 canonical supplement
// product-type buckets used for primary_category, search filter chips,
// and product badges.
//
// Loaded once at first call to `loadProductTypeVocab()`; cached
// process-lifetime.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class ProductTypeEntry {
  final String id;
  final String name;
  final String shortName;
  final String notes;

  const ProductTypeEntry({
    required this.id,
    required this.name,
    required this.shortName,
    required this.notes,
  });

  factory ProductTypeEntry.fromJson(Map<String, dynamic> json) {
    return ProductTypeEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortName:
          json['short_name']?.toString() ?? json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
  }
}

Map<String, ProductTypeEntry>? _cache;

Future<Map<String, ProductTypeEntry>> loadProductTypeVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/product_type_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['product_types'] as List?) ?? const [];

  final byId = <String, ProductTypeEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final c = ProductTypeEntry.fromJson(entry);
    if (c.id.isEmpty) continue;
    byId[c.id] = c;
  }

  _cache = byId;
  return byId;
}

void debugSetProductTypeVocabForTesting(Map<String, ProductTypeEntry>? value) {
  _cache = value;
}
