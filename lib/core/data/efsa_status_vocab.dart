// EFSA-status vocab loader (locked v1.0.0).
// 10 IDs for EFSA OpenFoodTox status field.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class EfsaStatusEntry {
  final String id;
  final String name;
  final String notes;

  const EfsaStatusEntry({
    required this.id,
    required this.name,
    required this.notes,
  });

  factory EfsaStatusEntry.fromJson(Map<String, dynamic> json) {
    return EfsaStatusEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
  }
}

Map<String, EfsaStatusEntry>? _cache;

Future<Map<String, EfsaStatusEntry>> loadEfsaStatusVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString('assets/data/efsa_status_vocab.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['efsa_statuses'] as List?) ?? const [];

  final byId = <String, EfsaStatusEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final s = EfsaStatusEntry.fromJson(entry);
    if (s.id.isEmpty) continue;
    byId[s.id] = s;
  }

  _cache = byId;
  return byId;
}

void debugSetEfsaStatusVocabForTesting(Map<String, EfsaStatusEntry>? value) {
  _cache = value;
}
