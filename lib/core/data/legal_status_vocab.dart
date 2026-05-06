// Legal-status vocab loader (locked v1.0.0).
// 10 IDs covering regulatory/legal classifications used by
// banned_recalled_ingredients.json `legal_status_enum`.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class LegalStatusEntry {
  final String id;
  final String name;
  final String notes;
  final String authority;
  final String implication;

  const LegalStatusEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.authority,
    required this.implication,
  });

  factory LegalStatusEntry.fromJson(Map<String, dynamic> json) {
    return LegalStatusEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      authority: json['authority']?.toString() ?? '',
      implication: json['implication']?.toString() ?? '',
    );
  }
}

Map<String, LegalStatusEntry>? _cache;

Future<Map<String, LegalStatusEntry>> loadLegalStatusVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/legal_status_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['legal_statuses'] as List?) ?? const [];

  final byId = <String, LegalStatusEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final l = LegalStatusEntry.fromJson(entry);
    if (l.id.isEmpty) continue;
    byId[l.id] = l;
  }

  _cache = byId;
  return byId;
}

void debugSetLegalStatusVocabForTesting(Map<String, LegalStatusEntry>? value) {
  _cache = value;
}
