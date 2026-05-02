// Study-type vocab loader.
//
// Covers clinical study-design categories from backed_clinical_studies.json.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class StudyTypeEntry {
  final String id;
  final String name;
  final String notes;
  final int basePoints;
  final int tier;

  const StudyTypeEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.basePoints,
    required this.tier,
  });

  factory StudyTypeEntry.fromJson(Map<String, dynamic> json) {
    return StudyTypeEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      basePoints: (json['base_points'] as num?)?.toInt() ?? 0,
      tier: (json['tier'] as num?)?.toInt() ?? 0,
    );
  }
}

Map<String, StudyTypeEntry>? _cache;

Future<Map<String, StudyTypeEntry>> loadStudyTypeVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString('assets/data/study_type_vocab.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['study_types'] as List?) ?? const [];

  final byId = <String, StudyTypeEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final studyType = StudyTypeEntry.fromJson(entry);
    if (studyType.id.isEmpty) continue;
    byId[studyType.id] = studyType;
  }

  _cache = byId;
  return byId;
}

void debugSetStudyTypeVocabForTesting(Map<String, StudyTypeEntry>? value) {
  _cache = value;
}
