// Effect-direction vocab loader (locked v1.0.0).
// 5 IDs from backed_clinical_studies.json effect_direction field.
// Multipliers verified against scoring_config.json.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class EffectDirectionEntry {
  final String id;
  final String name;
  final String notes;
  final double multiplier;

  const EffectDirectionEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.multiplier,
  });

  factory EffectDirectionEntry.fromJson(Map<String, dynamic> json) {
    return EffectDirectionEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

Map<String, EffectDirectionEntry>? _cache;

Future<Map<String, EffectDirectionEntry>> loadEffectDirectionVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/effect_direction_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['effect_directions'] as List?) ?? const [];

  final byId = <String, EffectDirectionEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final e = EffectDirectionEntry.fromJson(entry);
    if (e.id.isEmpty) continue;
    byId[e.id] = e;
  }

  _cache = byId;
  return byId;
}

void debugSetEffectDirectionVocabForTesting(
  Map<String, EffectDirectionEntry>? value,
) {
  _cache = value;
}
