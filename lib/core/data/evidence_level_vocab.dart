// Evidence-level vocab loader.
//
// This covers clinical-study design tiers from backed_clinical_studies.json.
// Interaction-rule evidence strength is a separate vocab because the source
// files currently reuse the field name `evidence_level` for a different concept.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class EvidenceLevelEntry {
  final String id;
  final String name;
  final String notes;
  final double multiplier;
  final int tier;

  const EvidenceLevelEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.multiplier,
    required this.tier,
  });

  factory EvidenceLevelEntry.fromJson(Map<String, dynamic> json) {
    return EvidenceLevelEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 0,
      tier: (json['tier'] as num?)?.toInt() ?? 0,
    );
  }
}

Map<String, EvidenceLevelEntry>? _cache;

Future<Map<String, EvidenceLevelEntry>> loadEvidenceLevelVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/evidence_level_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['evidence_levels'] as List?) ?? const [];

  final byId = <String, EvidenceLevelEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final level = EvidenceLevelEntry.fromJson(entry);
    if (level.id.isEmpty) continue;
    byId[level.id] = level;
  }

  _cache = byId;
  return byId;
}

void debugSetEvidenceLevelVocabForTesting(
  Map<String, EvidenceLevelEntry>? value,
) {
  _cache = value;
}
