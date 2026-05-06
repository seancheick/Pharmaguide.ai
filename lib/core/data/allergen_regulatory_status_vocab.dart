// Allergen-regulatory-status vocab loader (locked v1.0.0).
// 3 IDs: fda_major, eu_major, eu_allergen.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class AllergenRegulatoryStatusEntry {
  final String id;
  final String name;
  final String notes;
  final String authority;

  const AllergenRegulatoryStatusEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.authority,
  });

  factory AllergenRegulatoryStatusEntry.fromJson(Map<String, dynamic> json) {
    return AllergenRegulatoryStatusEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      authority: json['authority']?.toString() ?? '',
    );
  }
}

Map<String, AllergenRegulatoryStatusEntry>? _cache;

Future<Map<String, AllergenRegulatoryStatusEntry>>
loadAllergenRegulatoryStatusVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/allergen_regulatory_status_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries =
      (decoded['allergen_regulatory_statuses'] as List?) ?? const [];

  final byId = <String, AllergenRegulatoryStatusEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final s = AllergenRegulatoryStatusEntry.fromJson(entry);
    if (s.id.isEmpty) continue;
    byId[s.id] = s;
  }

  _cache = byId;
  return byId;
}

void debugSetAllergenRegulatoryStatusVocabForTesting(
  Map<String, AllergenRegulatoryStatusEntry>? value,
) {
  _cache = value;
}
