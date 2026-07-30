// Clinical-condition taxonomy adapter.
//
// The pipeline-owned `clinical_risk_taxonomy.json` is the only authored
// condition schema. This adapter preserves the compact [ConditionEntry]
// interface used by [VocabRegistry] while translating the taxonomy's
// `label` / `description` names. Do not add a second condition asset or
// hardcoded list here.
//
// Loaded once at first call to `loadConditionVocab()`; subsequent
// calls return the cached value. Cache is process-lifetime.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class Icd10Reference {
  final String code;
  final String description;
  const Icd10Reference({required this.code, required this.description});

  factory Icd10Reference.fromJson(Map<String, dynamic> json) {
    return Icd10Reference(
      code: json['code']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }
}

class ConditionEntry {
  final String id;
  final String name;
  final String notes;
  final List<String> synonyms;
  final List<Icd10Reference> icd10;

  const ConditionEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.synonyms,
    required this.icd10,
  });

  factory ConditionEntry.fromTaxonomyJson(Map<String, dynamic> json) {
    return ConditionEntry(
      id: json['id']?.toString() ?? '',
      name: json['label']?.toString() ?? '',
      notes: json['description']?.toString() ?? '',
      synonyms:
          (json['synonyms'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      icd10:
          (json['icd10'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(Icd10Reference.fromJson)
              .toList(growable: false) ??
          const [],
    );
  }
}

Map<String, ConditionEntry>? _cache;

Future<Map<String, ConditionEntry>> loadConditionVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/reference_data/clinical_risk_taxonomy.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['conditions'] as List?) ?? const [];

  final byId = <String, ConditionEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final c = ConditionEntry.fromTaxonomyJson(entry);
    if (c.id.isEmpty) continue;
    byId[c.id] = c;
  }

  _cache = byId;
  return byId;
}

void debugSetConditionVocabForTesting(Map<String, ConditionEntry>? value) {
  _cache = value;
}
