// User-goals vocab loader.
//
// Pipeline contract (locked v1.0.0, schema in pipeline repo
// `scripts/data/user_goals_vocab.json`):
//
//   {
//     "schema_version": "1.0.0",
//     "user_goals": [
//       {
//         "id": "GOAL_SLEEP_QUALITY",
//         "name": "Sleep Quality",
//         "notes": "≤ 200-char description...",
//         "priority": "high",
//         "related_condition_ids": [...],
//         "related_drug_class_ids": [...]
//       },
//       ...
//     ]
//   }
//
// 18 entries, locked. Same IDs as user_goals_to_clusters.json
// (presentation here, cluster-mapping there). Migrated from hardcoded
// goalLabels + goalPriorities in lib/core/constants/schema_ids.dart.
//
// Loaded once at first call to `loadUserGoalsVocab()`; cached
// process-lifetime.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class UserGoalEntry {
  final String id;
  final String name;
  final String notes;
  final String priority;
  final List<String> relatedConditionIds;
  final List<String> relatedDrugClassIds;

  const UserGoalEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.priority,
    required this.relatedConditionIds,
    required this.relatedDrugClassIds,
  });

  factory UserGoalEntry.fromJson(Map<String, dynamic> json) {
    return UserGoalEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      priority: json['priority']?.toString() ?? '',
      relatedConditionIds:
          (json['related_condition_ids'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      relatedDrugClassIds:
          (json['related_drug_class_ids'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
    );
  }
}

Map<String, UserGoalEntry>? _cache;

Future<Map<String, UserGoalEntry>> loadUserGoalsVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString('assets/data/user_goals_vocab.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['user_goals'] as List?) ?? const [];

  final byId = <String, UserGoalEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final g = UserGoalEntry.fromJson(entry);
    if (g.id.isEmpty) continue;
    byId[g.id] = g;
  }

  _cache = byId;
  return byId;
}

void debugSetUserGoalsVocabForTesting(Map<String, UserGoalEntry>? value) {
  _cache = value;
}
