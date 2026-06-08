import 'dart:convert';

import 'package:pharmaguide/data/database/user_database.dart';

enum MedicationIdentityStatus {
  complete,
  partial,
  classOnly,
  exactOnly,
  unresolved,
}

class MedicationIdentitySnapshot {
  final String name;
  final String? rxcui;
  final String? genericRxcui;
  final List<String> ingredientRxcuis;
  final List<String> drugClassIds;

  const MedicationIdentitySnapshot({
    required this.name,
    this.rxcui,
    this.genericRxcui,
    this.ingredientRxcuis = const [],
    this.drugClassIds = const [],
  });

  factory MedicationIdentitySnapshot.fromStackRow(UserStacksLocalData row) {
    return MedicationIdentitySnapshot(
      name: row.name,
      rxcui: _normalize(row.rxcui),
      genericRxcui: _normalize(row.genericRxcui),
      ingredientRxcuis: decodeMedicationIdentityList(row.ingredientRxcuisCol),
      drugClassIds: decodeMedicationIdentityList(row.drugClassesCol),
    );
  }

  bool get hasExactRxcui => _hasText(rxcui);
  bool get hasGenericRxcui => _hasText(genericRxcui);
  bool get hasIngredientRxcuis => ingredientRxcuis.isNotEmpty;
  bool get hasDrugClasses => drugClassIds.isNotEmpty;
  bool get hasAnyRxcui =>
      hasExactRxcui || hasGenericRxcui || hasIngredientRxcuis;

  MedicationIdentityStatus get status {
    if (hasDrugClasses && (hasGenericRxcui || hasIngredientRxcuis)) {
      return MedicationIdentityStatus.complete;
    }
    if (hasDrugClasses && !hasAnyRxcui) {
      return MedicationIdentityStatus.classOnly;
    }
    if (hasDrugClasses || hasGenericRxcui || hasIngredientRxcuis) {
      return MedicationIdentityStatus.partial;
    }
    if (hasExactRxcui) return MedicationIdentityStatus.exactOnly;
    return MedicationIdentityStatus.unresolved;
  }
}

List<String> decodeMedicationIdentityList(String? raw) {
  if (raw == null || raw.isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    for (final item in decoded) {
      final value = item?.toString().trim();
      if (value == null || value.isEmpty) continue;
      if (seen.add(value)) out.add(value);
    }
    return out;
  } on FormatException {
    return const <String>[];
  }
}

String? _normalize(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
