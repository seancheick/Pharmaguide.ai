// Drug-class vocab loader.
//
// Pipeline contract (schema source: pipeline repo
// `scripts/data/drug_class_vocab.json`):
//
//   {
//     "schema_version": "1.1.0",
//     "drug_classes": [
//       {
//         "id": "anticoagulants",
//         "name": "Blood thinners",
//         "group_label": "Blood thinners",          // v1.1.0, optional
//         "commonly_used_for": "Commonly used ...", // v1.1.0, optional
//         "notes": "≤ 200-char user-facing description...",
//         "examples": ["warfarin", "apixaban", "rivaroxaban", ...],
//         "rx_status": "rx_only",
//         "user_selectable": true
//       },
//       ...
//     ]
//   }
//
// Entry counts and the user_selectable/rule-only split live in the JSON
// `_metadata` — do not hand-copy them here (a previous "21 entries
// (13 + 8)" note in this comment had silently drifted from the pipeline's
// 30). The user_selectable subset matches `drugClasses` in
// lib/core/constants/schema_ids.dart; rule-only classes (CYP substrates,
// narrow drug families) are referenced by interaction rules and by
// medication classification, but are not profile picks.
//
// v1.1.0 adds two OPTIONAL sheet-facing consumer fields, `group_label`
// and `commonly_used_for` (clinician-reviewed education for the
// medication details sheet). Older bundled assets don't carry them; the
// parser yields null and the sheet omits its education section.
//
// Loaded once at first call to `loadDrugClassVocab()`; cached
// process-lifetime.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class DrugClassEntry {
  final String id;
  final String name;

  /// Clean consumer classification noun for the medication details sheet
  /// ("Diabetes medications"). Null when the bundled asset predates vocab
  /// v1.1.0 — the sheet omits its education section then.
  final String? groupLabel;

  /// One clinician-reviewed sentence ("Commonly used to help ..."). Null
  /// when the bundled asset predates vocab v1.1.0.
  final String? commonlyUsedFor;
  final String notes;
  final List<String> examples;
  final String rxStatus;
  final bool userSelectable;

  const DrugClassEntry({
    required this.id,
    required this.name,
    this.groupLabel,
    this.commonlyUsedFor,
    required this.notes,
    required this.examples,
    required this.rxStatus,
    required this.userSelectable,
  });

  factory DrugClassEntry.fromJson(Map<String, dynamic> json) {
    return DrugClassEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      groupLabel: _optionalTrimmed(json['group_label']),
      commonlyUsedFor: _optionalTrimmed(json['commonly_used_for']),
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

/// Missing or blank optional strings normalize to null so render gates
/// stay a simple null check.
String? _optionalTrimmed(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
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
