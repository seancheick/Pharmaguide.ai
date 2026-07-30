// Clinical-indication vocab loader.
//
// Pipeline contract (locked v1.0.0, schema in pipeline repo
// `scripts/data/clinical_indication_vocab.json`):
//
//   {
//     "schema_version": "1.0.0",
//     "clinical_indications": [
//       {
//         "id": "cardiovascular",
//         "name": "Cardiovascular & Heart Health",
//         "notes": "≤ 200-char description...",
//         "related_condition_ids": ["heart_disease", "hypertension"],
//         "examples": ["omega-3 EPA/DHA", "CoQ10", ...]
//       },
//       ...
//     ]
//   }
//
// 22 entries, locked. Drives evidence grouping in product detail
// (e.g. "Cardiovascular evidence" badge) and links to the clinical taxonomy
// for context-relevant scoring boosts.
//
// Loaded once at first call to `loadClinicalIndicationVocab()`;
// cached process-lifetime.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class ClinicalIndicationEntry {
  final String id;
  final String name;
  final String notes;
  final List<String> relatedConditionIds;
  final List<String> examples;

  const ClinicalIndicationEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.relatedConditionIds,
    required this.examples,
  });

  factory ClinicalIndicationEntry.fromJson(Map<String, dynamic> json) {
    return ClinicalIndicationEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      relatedConditionIds:
          (json['related_condition_ids'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      examples:
          (json['examples'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
    );
  }
}

Map<String, ClinicalIndicationEntry>? _cache;

Future<Map<String, ClinicalIndicationEntry>>
loadClinicalIndicationVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/clinical_indication_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['clinical_indications'] as List?) ?? const [];

  final byId = <String, ClinicalIndicationEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final i = ClinicalIndicationEntry.fromJson(entry);
    if (i.id.isEmpty) continue;
    byId[i.id] = i;
  }

  _cache = byId;
  return byId;
}

void debugSetClinicalIndicationVocabForTesting(
  Map<String, ClinicalIndicationEntry>? value,
) {
  _cache = value;
}
