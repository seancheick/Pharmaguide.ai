// Severity vocab loader.
//
// Pipeline contract (locked v1.0.0, schema in pipeline repo
// `scripts/data/severity_vocab.json`):
//
//   {
//     "schema_version": "1.0.0",
//     "severities": [
//       {
//         "id": "caution",
//         "name": "Use caution",
//         "short_label": "Caution",
//         "tone": "warning",
//         "ui_color": "orange",
//         "ui_icon": "warning",
//         "action": "Use under guidance",
//         "notes": "≤ 200-char user-facing description..."
//       },
//       ...
//     ]
//   }
//
// 6 entries, locked: contraindicated, avoid, caution, monitor,
// informational, safe. The legacy `info` ID was renamed to
// `informational` 2026-04-30 across pipeline data + emitters; the dart
// `Severity.informational` enum already uses the new label.
//
// Loaded once at first call to `loadSeverityVocab()`; subsequent calls
// return the cached value. The cache is process-lifetime — there is
// no invalidation API because vocab updates ship via app release.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class SeverityEntry {
  final String id;
  final String name;
  final String shortLabel;
  final String tone;
  final String uiColor;
  final String uiIcon;
  final String action;
  final String notes;

  const SeverityEntry({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.tone,
    required this.uiColor,
    required this.uiIcon,
    required this.action,
    required this.notes,
  });

  factory SeverityEntry.fromJson(Map<String, dynamic> json) {
    return SeverityEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortLabel: json['short_label']?.toString() ?? '',
      tone: json['tone']?.toString() ?? '',
      uiColor: json['ui_color']?.toString() ?? '',
      uiIcon: json['ui_icon']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
  }
}

Map<String, SeverityEntry>? _cache;

Future<Map<String, SeverityEntry>> loadSeverityVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString('assets/data/severity_vocab.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['severities'] as List?) ?? const [];

  final byId = <String, SeverityEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final s = SeverityEntry.fromJson(entry);
    if (s.id.isEmpty) continue;
    byId[s.id] = s;
  }

  _cache = byId;
  return byId;
}

void debugSetSeverityVocabForTesting(Map<String, SeverityEntry>? value) {
  _cache = value;
}
