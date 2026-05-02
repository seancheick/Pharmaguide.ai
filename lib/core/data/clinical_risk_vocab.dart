// Clinical-risk vocab loader (locked v1.0.0).
// 5 IDs: critical, high, moderate, dose_dependent, low.
// Display contract for clinical_risk_enum tier in banned/recalled alerts.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class ClinicalRiskEntry {
  final String id;
  final String name;
  final String shortLabel;
  final String tone;
  final String uiColor;
  final String uiIcon;
  final String action;
  final String notes;
  final int severityWeight;

  const ClinicalRiskEntry({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.tone,
    required this.uiColor,
    required this.uiIcon,
    required this.action,
    required this.notes,
    required this.severityWeight,
  });

  factory ClinicalRiskEntry.fromJson(Map<String, dynamic> json) {
    return ClinicalRiskEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortLabel: json['short_label']?.toString() ?? '',
      tone: json['tone']?.toString() ?? '',
      uiColor: json['ui_color']?.toString() ?? '',
      uiIcon: json['ui_icon']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      severityWeight: (json['severity_weight'] as num?)?.toInt() ?? 0,
    );
  }
}

Map<String, ClinicalRiskEntry>? _cache;

Future<Map<String, ClinicalRiskEntry>> loadClinicalRiskVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/clinical_risk_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['clinical_risks'] as List?) ?? const [];

  final byId = <String, ClinicalRiskEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final r = ClinicalRiskEntry.fromJson(entry);
    if (r.id.isEmpty) continue;
    byId[r.id] = r;
  }

  _cache = byId;
  return byId;
}

void debugSetClinicalRiskVocabForTesting(
  Map<String, ClinicalRiskEntry>? value,
) {
  _cache = value;
}
