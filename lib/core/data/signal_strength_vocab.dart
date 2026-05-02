// Signal-strength vocab loader (locked v1.0.0).
// 3 IDs for CAERS adverse-event signals (strong/moderate/weak).
// Display contract for future re-enabled CAERS scoring.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class SignalStrengthEntry {
  final String id;
  final String name;
  final String shortLabel;
  final String tone;
  final String uiColor;
  final String uiIcon;
  final String action;
  final String notes;
  final String thresholdDefinition;

  const SignalStrengthEntry({
    required this.id,
    required this.name,
    required this.shortLabel,
    required this.tone,
    required this.uiColor,
    required this.uiIcon,
    required this.action,
    required this.notes,
    required this.thresholdDefinition,
  });

  factory SignalStrengthEntry.fromJson(Map<String, dynamic> json) {
    return SignalStrengthEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortLabel: json['short_label']?.toString() ?? '',
      tone: json['tone']?.toString() ?? '',
      uiColor: json['ui_color']?.toString() ?? '',
      uiIcon: json['ui_icon']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      thresholdDefinition: json['threshold_definition']?.toString() ?? '',
    );
  }
}

Map<String, SignalStrengthEntry>? _cache;

Future<Map<String, SignalStrengthEntry>> loadSignalStrengthVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/signal_strength_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['signal_strengths'] as List?) ?? const [];

  final byId = <String, SignalStrengthEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final s = SignalStrengthEntry.fromJson(entry);
    if (s.id.isEmpty) continue;
    byId[s.id] = s;
  }

  _cache = byId;
  return byId;
}

void debugSetSignalStrengthVocabForTesting(
  Map<String, SignalStrengthEntry>? value,
) {
  _cache = value;
}
