// Condition vocab loader.
//
// Pipeline contract (locked v1.0.0, schema in pipeline repo
// `scripts/data/condition_vocab.json`):
//
//   {
//     "schema_version": "1.0.0",
//     "conditions": [
//       {
//         "id": "pregnancy",
//         "name": "Pregnancy",
//         "notes": "≤ 200-char user-facing description...",
//         "synonyms": ["expecting", "gestation"],
//         "icd10": [{"code": "O00-O9A", "description": "..."}]
//       },
//       ...
//     ]
//   }
//
// 14 entries, locked. The canonical set matches `conditions` in
// lib/core/constants/schema_ids.dart. Migrating gives clinician
// control of the user-facing condition copy.
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

  factory ConditionEntry.fromJson(Map<String, dynamic> json) {
    return ConditionEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
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

  final raw = await rootBundle.loadString('assets/data/condition_vocab.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['conditions'] as List?) ?? const [];

  final byId = <String, ConditionEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final c = ConditionEntry.fromJson(entry);
    if (c.id.isEmpty) continue;
    byId[c.id] = c;
  }

  _cache = byId;
  return byId;
}

void debugSetConditionVocabForTesting(Map<String, ConditionEntry>? value) {
  _cache = value;
}
