// Allergen-prevalence vocab loader (locked v1.0.0).
// 3 IDs (high/moderate/low) for allergens.json prevalence field.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class AllergenPrevalenceEntry {
  final String id;
  final String name;
  final String shortLabel;
  final String tone;
  final String uiColor;
  final String uiIcon;
  final String action;
  final String notes;

  const AllergenPrevalenceEntry({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.tone,
    required this.uiColor,
    required this.uiIcon,
    required this.action,
    required this.notes,
  });

  factory AllergenPrevalenceEntry.fromJson(Map<String, dynamic> json) {
    return AllergenPrevalenceEntry(
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

Map<String, AllergenPrevalenceEntry>? _cache;

Future<Map<String, AllergenPrevalenceEntry>>
loadAllergenPrevalenceVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/allergen_prevalence_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['allergen_prevalences'] as List?) ?? const [];

  final byId = <String, AllergenPrevalenceEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final p = AllergenPrevalenceEntry.fromJson(entry);
    if (p.id.isEmpty) continue;
    byId[p.id] = p;
  }

  _cache = byId;
  return byId;
}

void debugSetAllergenPrevalenceVocabForTesting(
  Map<String, AllergenPrevalenceEntry>? value,
) {
  _cache = value;
}
