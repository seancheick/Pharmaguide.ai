// Ban-context vocab loader (locked v1.0.0).
// 5 IDs disambiguating WHY a substance was flagged in banned_recalled_ingredients.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class BanContextEntry {
  final String id;
  final String name;
  final String notes;
  final String whenItApplies;
  final String actionRecommendation;

  const BanContextEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.whenItApplies,
    required this.actionRecommendation,
  });

  factory BanContextEntry.fromJson(Map<String, dynamic> json) {
    return BanContextEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      whenItApplies: json['when_it_applies']?.toString() ?? '',
      actionRecommendation: json['action_recommendation']?.toString() ?? '',
    );
  }
}

Map<String, BanContextEntry>? _cache;

Future<Map<String, BanContextEntry>> loadBanContextVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString('assets/data/ban_context_vocab.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['ban_contexts'] as List?) ?? const [];

  final byId = <String, BanContextEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final b = BanContextEntry.fromJson(entry);
    if (b.id.isEmpty) continue;
    byId[b.id] = b;
  }

  _cache = byId;
  return byId;
}

void debugSetBanContextVocabForTesting(Map<String, BanContextEntry>? value) {
  _cache = value;
}
