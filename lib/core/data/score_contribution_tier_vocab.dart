// Score-contribution-tier vocab loader (locked v1.0.0).
// 3 IDs (tier_1/tier_2/tier_3) for backed_clinical_studies score brackets.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class ScoreContributionTierEntry {
  final String id;
  final String name;
  final String shortLabel;
  final String tone;
  final String uiColor;
  final String uiIcon;
  final String action;
  final String notes;
  final int tierRank;

  const ScoreContributionTierEntry({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.tone,
    required this.uiColor,
    required this.uiIcon,
    required this.action,
    required this.notes,
    required this.tierRank,
  });

  factory ScoreContributionTierEntry.fromJson(Map<String, dynamic> json) {
    return ScoreContributionTierEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortLabel: json['short_label']?.toString() ?? '',
      tone: json['tone']?.toString() ?? '',
      uiColor: json['ui_color']?.toString() ?? '',
      uiIcon: json['ui_icon']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      tierRank: (json['tier_rank'] as num?)?.toInt() ?? 0,
    );
  }
}

Map<String, ScoreContributionTierEntry>? _cache;

Future<Map<String, ScoreContributionTierEntry>>
    loadScoreContributionTierVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/score_contribution_tier_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['score_contribution_tiers'] as List?) ?? const [];

  final byId = <String, ScoreContributionTierEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final t = ScoreContributionTierEntry.fromJson(entry);
    if (t.id.isEmpty) continue;
    byId[t.id] = t;
  }

  _cache = byId;
  return byId;
}

void debugSetScoreContributionTierVocabForTesting(
  Map<String, ScoreContributionTierEntry>? value,
) {
  _cache = value;
}
