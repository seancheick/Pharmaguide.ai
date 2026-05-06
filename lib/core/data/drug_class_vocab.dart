// Drug-class vocab loader.
//
// Pipeline contract (locked v1.0.0, schema in pipeline repo
// `scripts/data/drug_class_vocab.json`):
//
//   {
//     "schema_version": "1.0.0",
//     "drug_classes": [
//       {
//         "id": "anticoagulants",
//         "name": "Blood thinners",
//         "notes": "≤ 200-char user-facing description...",
//         "examples": ["warfarin", "apixaban", "rivaroxaban", ...],
//         "rx_status": "rx_only",
//         "user_selectable": true
//       },
//       ...
//     ]
//   }
//
// 21 entries, locked: 13 user_selectable (match `drugClasses` in
// lib/core/constants/schema_ids.dart) + 8 rule-only (CYP substrates,
// narrow drug families referenced by interaction rules but not surfaced
// as profile picks). Migrating gives clinician control of the
// user-facing drug-class copy and brand examples.
//
// Loaded once at first call to `loadDrugClassVocab()`; cached
// process-lifetime.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class DrugClassEntry {
  final String id;
  final String name;
  final String notes;
  final List<String> examples;
  final String rxStatus;
  final bool userSelectable;

  const DrugClassEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.examples,
    required this.rxStatus,
    required this.userSelectable,
  });

  factory DrugClassEntry.fromJson(Map<String, dynamic> json) {
    return DrugClassEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      examples:
          (json['examples'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      rxStatus: json['rx_status']?.toString() ?? '',
      userSelectable: json['user_selectable'] as bool? ?? false,
    );
  }
}

Map<String, DrugClassEntry>? _cache;

Future<Map<String, DrugClassEntry>> loadDrugClassVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString('assets/data/drug_class_vocab.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['drug_classes'] as List?) ?? const [];

  final byId = <String, DrugClassEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final d = DrugClassEntry.fromJson(entry);
    if (d.id.isEmpty) continue;
    byId[d.id] = d;
  }

  _cache = byId;
  return byId;
}

void debugSetDrugClassVocabForTesting(Map<String, DrugClassEntry>? value) {
  _cache = value;
}
