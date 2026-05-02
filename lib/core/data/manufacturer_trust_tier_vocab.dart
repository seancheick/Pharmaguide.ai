// Manufacturer-trust-tier vocab loader (locked v1.0.0).
// 4 IDs (trusted/neutral/violations_minor/violations_critical) computed
// from top_manufacturers_data + manufacturer_violations join.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class ManufacturerTrustTierEntry {
  final String id;
  final String name;
  final String shortLabel;
  final String tone;
  final String uiColor;
  final String uiIcon;
  final String action;
  final String notes;
  final String derivationRule;

  const ManufacturerTrustTierEntry({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.tone,
    required this.uiColor,
    required this.uiIcon,
    required this.action,
    required this.notes,
    required this.derivationRule,
  });

  factory ManufacturerTrustTierEntry.fromJson(Map<String, dynamic> json) {
    return ManufacturerTrustTierEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortLabel: json['short_label']?.toString() ?? '',
      tone: json['tone']?.toString() ?? '',
      uiColor: json['ui_color']?.toString() ?? '',
      uiIcon: json['ui_icon']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      derivationRule: json['derivation_rule']?.toString() ?? '',
    );
  }
}

Map<String, ManufacturerTrustTierEntry>? _cache;

Future<Map<String, ManufacturerTrustTierEntry>>
    loadManufacturerTrustTierVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/manufacturer_trust_tier_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['manufacturer_trust_tiers'] as List?) ?? const [];

  final byId = <String, ManufacturerTrustTierEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final m = ManufacturerTrustTierEntry.fromJson(entry);
    if (m.id.isEmpty) continue;
    byId[m.id] = m;
  }

  _cache = byId;
  return byId;
}

void debugSetManufacturerTrustTierVocabForTesting(
  Map<String, ManufacturerTrustTierEntry>? value,
) {
  _cache = value;
}
