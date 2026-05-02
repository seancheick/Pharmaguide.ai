// EFSA-genotoxicity vocab loader (locked v1.0.0).
// 7 IDs for EFSA OpenFoodTox genotoxicity field.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class EfsaGenotoxicityEntry {
  final String id;
  final String name;
  final String notes;

  const EfsaGenotoxicityEntry({
    required this.id,
    required this.name,
    required this.notes,
  });

  factory EfsaGenotoxicityEntry.fromJson(Map<String, dynamic> json) {
    return EfsaGenotoxicityEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
  }
}

Map<String, EfsaGenotoxicityEntry>? _cache;

Future<Map<String, EfsaGenotoxicityEntry>> loadEfsaGenotoxicityVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/efsa_genotoxicity_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['genotoxicity_classifications'] as List?) ?? const [];

  final byId = <String, EfsaGenotoxicityEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final g = EfsaGenotoxicityEntry.fromJson(entry);
    if (g.id.isEmpty) continue;
    byId[g.id] = g;
  }

  _cache = byId;
  return byId;
}

void debugSetEfsaGenotoxicityVocabForTesting(
  Map<String, EfsaGenotoxicityEntry>? value,
) {
  _cache = value;
}
