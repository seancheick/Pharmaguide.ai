// Banned-status vocab loader (locked v1.0.0).
// 4 IDs: banned, recalled, high_risk, watchlist.
// Display contract for B0-gate alerts and ban-context badges.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class BannedStatusEntry {
  final String id;
  final String name;
  final String shortLabel;
  final String tone;
  final String uiColor;
  final String uiIcon;
  final String action;
  final String notes;
  final String regulatoryBasis;

  const BannedStatusEntry({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.tone,
    required this.uiColor,
    required this.uiIcon,
    required this.action,
    required this.notes,
    required this.regulatoryBasis,
  });

  factory BannedStatusEntry.fromJson(Map<String, dynamic> json) {
    return BannedStatusEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortLabel: json['short_label']?.toString() ?? '',
      tone: json['tone']?.toString() ?? '',
      uiColor: json['ui_color']?.toString() ?? '',
      uiIcon: json['ui_icon']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      regulatoryBasis: json['regulatory_basis']?.toString() ?? '',
    );
  }
}

Map<String, BannedStatusEntry>? _cache;

Future<Map<String, BannedStatusEntry>> loadBannedStatusVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/banned_status_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['banned_statuses'] as List?) ?? const [];

  final byId = <String, BannedStatusEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final s = BannedStatusEntry.fromJson(entry);
    if (s.id.isEmpty) continue;
    byId[s.id] = s;
  }

  _cache = byId;
  return byId;
}

void debugSetBannedStatusVocabForTesting(
  Map<String, BannedStatusEntry>? value,
) {
  _cache = value;
}
