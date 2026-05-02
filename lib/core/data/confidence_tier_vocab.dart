// Confidence-tier vocab loader (locked v1.0.0).
// 3 IDs (high/medium/low) used in harmful_additives + clinical_studies.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class ConfidenceTierEntry {
  final String id;
  final String name;
  final String shortLabel;
  final String tone;
  final String uiColor;
  final String uiIcon;
  final String action;
  final String notes;

  const ConfidenceTierEntry({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.tone,
    required this.uiColor,
    required this.uiIcon,
    required this.action,
    required this.notes,
  });

  factory ConfidenceTierEntry.fromJson(Map<String, dynamic> json) {
    return ConfidenceTierEntry(
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

Map<String, ConfidenceTierEntry>? _cache;

Future<Map<String, ConfidenceTierEntry>> loadConfidenceTierVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/confidence_tier_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['confidence_tiers'] as List?) ?? const [];

  final byId = <String, ConfidenceTierEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final c = ConfidenceTierEntry.fromJson(entry);
    if (c.id.isEmpty) continue;
    byId[c.id] = c;
  }

  _cache = byId;
  return byId;
}

void debugSetConfidenceTierVocabForTesting(
  Map<String, ConfidenceTierEntry>? value,
) {
  _cache = value;
}
