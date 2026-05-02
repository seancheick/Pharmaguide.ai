// Match-mode vocab loader (locked v1.0.0).
// 3 IDs (active/disabled/historical) for banned_recalled_ingredients rule state.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class MatchModeEntry {
  final String id;
  final String name;
  final String notes;
  final bool firesInScoring;

  const MatchModeEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.firesInScoring,
  });

  factory MatchModeEntry.fromJson(Map<String, dynamic> json) {
    return MatchModeEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      firesInScoring: json['fires_in_scoring'] as bool? ?? false,
    );
  }
}

Map<String, MatchModeEntry>? _cache;

Future<Map<String, MatchModeEntry>> loadMatchModeVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/match_mode_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['match_modes'] as List?) ?? const [];

  final byId = <String, MatchModeEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final m = MatchModeEntry.fromJson(entry);
    if (m.id.isEmpty) continue;
    byId[m.id] = m;
  }

  _cache = byId;
  return byId;
}

void debugSetMatchModeVocabForTesting(
  Map<String, MatchModeEntry>? value,
) {
  _cache = value;
}
