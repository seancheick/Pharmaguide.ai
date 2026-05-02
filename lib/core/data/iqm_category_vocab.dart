// IQM-category vocab loader.
//
// Pipeline contract (locked v1.0.0, schema in pipeline repo
// `scripts/data/iqm_category_vocab.json`): 12 parent-category buckets
// for the Ingredient Quality Map's 621+ active-ingredient parents.
//
// Loaded once at first call to `loadIqmCategoryVocab()`; cached
// process-lifetime.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class IqmCategoryEntry {
  final String id;
  final String name;
  final String notes;
  final List<String> examples;

  const IqmCategoryEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.examples,
  });

  factory IqmCategoryEntry.fromJson(Map<String, dynamic> json) {
    return IqmCategoryEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      examples: (json['examples'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
    );
  }
}

Map<String, IqmCategoryEntry>? _cache;

Future<Map<String, IqmCategoryEntry>> loadIqmCategoryVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/iqm_category_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['iqm_categories'] as List?) ?? const [];

  final byId = <String, IqmCategoryEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final c = IqmCategoryEntry.fromJson(entry);
    if (c.id.isEmpty) continue;
    byId[c.id] = c;
  }

  _cache = byId;
  return byId;
}

void debugSetIqmCategoryVocabForTesting(
  Map<String, IqmCategoryEntry>? value,
) {
  _cache = value;
}
