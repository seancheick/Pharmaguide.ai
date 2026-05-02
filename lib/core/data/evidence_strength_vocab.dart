// Evidence-strength vocab loader.
//
// This covers qualitative interaction-rule strength tiers. The pipeline source
// field is still named `evidence_level`; the vocab name uses `strength` to keep
// it distinct from clinical-study design evidence levels.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class EvidenceStrengthEntry {
  final String id;
  final String name;
  final String notes;
  final int tier;

  const EvidenceStrengthEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.tier,
  });

  factory EvidenceStrengthEntry.fromJson(Map<String, dynamic> json) {
    return EvidenceStrengthEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      tier: (json['tier'] as num?)?.toInt() ?? 0,
    );
  }
}

Map<String, EvidenceStrengthEntry>? _cache;

Future<Map<String, EvidenceStrengthEntry>> loadEvidenceStrengthVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/evidence_strength_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['evidence_strengths'] as List?) ?? const [];

  final byId = <String, EvidenceStrengthEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final strength = EvidenceStrengthEntry.fromJson(entry);
    if (strength.id.isEmpty) continue;
    byId[strength.id] = strength;
  }

  _cache = byId;
  return byId;
}

void debugSetEvidenceStrengthVocabForTesting(
  Map<String, EvidenceStrengthEntry>? value,
) {
  _cache = value;
}
