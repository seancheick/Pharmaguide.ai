// Form-factor vocab loader.
//
// Pipeline contract (v1.0.0, schema in pipeline repo
// `scripts/data/form_factor_vocab.json`): 18 canonical product
// physical-state buckets covering DSLD's 10 langual codes plus
// finer-grain distinctions (softgel split from capsule, sublingual
// split from lozenge, tincture from liquid, etc.).
//
// Consumed by product cards, ingredient drawers, and search filter
// chips to render the human-readable short name for the canonical
// `form_factor_canonical` field emitted by the pipeline enricher.
//
// Loaded once at first call to `loadFormFactorVocab()`; cached
// process-lifetime.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class FormFactorEntry {
  final String id;
  final String shortName;
  final String description;
  final List<String> aliases;
  final List<String> dsldLangualCodes;

  const FormFactorEntry({
    required this.id,
    required this.shortName,
    required this.description,
    required this.aliases,
    required this.dsldLangualCodes,
  });

  factory FormFactorEntry.fromJson(Map<String, dynamic> json) {
    final aliasesRaw = json['aliases'];
    final codesRaw = json['dsld_langual_codes'];
    return FormFactorEntry(
      id: json['id']?.toString() ?? '',
      shortName: json['short_name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      aliases: aliasesRaw is List
          ? aliasesRaw.map((a) => a.toString()).toList()
          : const [],
      dsldLangualCodes: codesRaw is List
          ? codesRaw.map((c) => c.toString()).toList()
          : const [],
    );
  }
}

Map<String, FormFactorEntry>? _cache;

Future<Map<String, FormFactorEntry>> loadFormFactorVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString('assets/data/form_factor_vocab.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['form_factors'] as List?) ?? const [];

  final byId = <String, FormFactorEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final c = FormFactorEntry.fromJson(entry);
    if (c.id.isEmpty) continue;
    byId[c.id] = c;
  }

  _cache = byId;
  return byId;
}

void debugSetFormFactorVocabForTesting(Map<String, FormFactorEntry>? value) {
  _cache = value;
}
