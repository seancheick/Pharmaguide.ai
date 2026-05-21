// Functional-roles vocab loader.
//
// Pipeline contract (v1.0.0, schema in pipeline repo
// `scripts/data/functional_roles_vocab.json`): 32 LOCKED canonical
// excipient/inactive-ingredient functional roles (binder, lubricant,
// emulsifier, etc.). Used as the source of truth for `functional_roles[]`
// arrays across harmful_additives.json, other_ingredients.json, and
// botanical_ingredients.json.
//
// Display-only in V1 — no scoring impact. The Flutter app uses this for
// the tap-to-learn UI on inactive-ingredient chips.
//
// Aligned with FDA 21 CFR 170.3(o), EU E-numbers, FAO/JECFA INS classes.
// Clinician-locked at v1.0.0; adding/removing roles requires a fresh
// review cycle (enforced by
// `test_functional_roles_vocab_contract.py::test_exactly_32_roles_locked`).
//
// Layer contract: WHY an ingredient is in the product. Distinct from:
//   - ingredient_category (WHAT it is) — SP-4
//   - safety_role (whether it affects safety gates) — banned_status
//   - ingredient_identity (WHO it is) — canonical_id / IQM parent
//
// Loaded once at first call to `loadFunctionalRolesVocab()`; cached
// process-lifetime.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class RegulatoryReference {
  final String jurisdiction;
  final String code;

  const RegulatoryReference({required this.jurisdiction, required this.code});

  factory RegulatoryReference.fromJson(Map<String, dynamic> json) {
    return RegulatoryReference(
      jurisdiction: json['jurisdiction']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
    );
  }
}

class FunctionalRoleEntry {
  final String id;
  final String name;
  final String notes;
  final List<RegulatoryReference> regulatoryReferences;
  final List<String> examples;

  const FunctionalRoleEntry({
    required this.id,
    required this.name,
    required this.notes,
    required this.regulatoryReferences,
    required this.examples,
  });

  factory FunctionalRoleEntry.fromJson(Map<String, dynamic> json) {
    final refsRaw = json['regulatory_references'];
    final examplesRaw = json['examples'];
    return FunctionalRoleEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      regulatoryReferences: refsRaw is List
          ? refsRaw
              .whereType<Map<String, dynamic>>()
              .map(RegulatoryReference.fromJson)
              .toList()
          : const [],
      examples: examplesRaw is List
          ? examplesRaw.map((a) => a.toString()).toList()
          : const [],
    );
  }
}

Map<String, FunctionalRoleEntry>? _cache;

Future<Map<String, FunctionalRoleEntry>> loadFunctionalRolesVocab() async {
  final cached = _cache;
  if (cached != null) return cached;

  final raw = await rootBundle.loadString(
    'assets/data/functional_roles_vocab.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = (decoded['functional_roles'] as List?) ?? const [];

  final byId = <String, FunctionalRoleEntry>{};
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) continue;
    final c = FunctionalRoleEntry.fromJson(entry);
    if (c.id.isEmpty) continue;
    byId[c.id] = c;
  }

  _cache = byId;
  return byId;
}

void debugSetFunctionalRolesVocabForTesting(
  Map<String, FunctionalRoleEntry>? value,
) {
  _cache = value;
}
