// Primary-outcome vocab loader (locked v1.0.0).
// 16 IDs for backed_clinical_studies primary_outcome categories.
// Carries legacy_display string for round-trip lookup until source-data
// migration to snake_case.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class PrimaryOutcomeEntry {
  final String id;
  final String name;
  final String legacyDisplay;
  final String notes;
  final String relatedUserGoalId;

  const PrimaryOutcomeEntry({
    required this.id,
    required this.name,
    required this.legacyDisplay,
    required this.notes,
    required this.relatedUserGoalId,
  });

  factory PrimaryOutcomeEntry.fromJson(Map<String, dynamic> json) {
    return PrimaryOutcomeEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      legacyDisplay: json['legacy_display']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      relatedUserGoalId: json['related_user_goal_id']?.toString() ?? '',
    );
  }
}

Map<String, PrimaryOutcomeEntry>? _cache;
Map<String, PrimaryOutcomeEntry>? _legacyIndex;

Future<Map<String, PrimaryOutcomeEntry>> loadPrimaryOutcomeVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/primary_outcome_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['primary_outcomes'] as List?) ?? const [];

  final byId = <String, PrimaryOutcomeEntry>{};
  final byLegacy = <String, PrimaryOutcomeEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final p = PrimaryOutcomeEntry.fromJson(entry);
    if (p.id.isEmpty) continue;
    byId[p.id] = p;
    if (p.legacyDisplay.isNotEmpty) byLegacy[p.legacyDisplay] = p;
  }

  _cache = byId;
  _legacyIndex = byLegacy;
  return byId;
}

/// Round-trip lookup by the legacy human-readable display string used
/// in source data (e.g. "Reduce Stress/Anxiety"). Returns null if no
/// match found.
PrimaryOutcomeEntry? lookupPrimaryOutcomeByLegacyDisplay(String legacyDisplay) {
  return _legacyIndex?[legacyDisplay];
}

void debugSetPrimaryOutcomeVocabForTesting(
  Map<String, PrimaryOutcomeEntry>? value,
  Map<String, PrimaryOutcomeEntry>? legacyIndex,
) {
  _cache = value;
  _legacyIndex = legacyIndex;
}
