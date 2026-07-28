import 'package:pharmaguide/core/constants/schema_ids.dart';

enum ClinicalProfileField { condition, drugClass, goal, allergen }

/// Converts persisted clinical profile identifiers into presentation labels.
///
/// Known identifiers use the same frozen vocabulary as profile setup. Legacy
/// or future identifiers receive a readable fallback so clinician exports
/// never expose raw snake-case or schema prefixes.
List<String> clinicalProfileLabels(
  Iterable<String> identifiers,
  ClinicalProfileField field,
) {
  return identifiers
      .map((identifier) => _clinicalProfileLabel(identifier, field))
      .whereType<String>()
      .toList(growable: false);
}

String? _clinicalProfileLabel(String identifier, ClinicalProfileField field) {
  final value = identifier.trim();
  if (value.isEmpty || SchemaIds.noneSentinels.contains(value)) return null;

  final knownLabel = switch (field) {
    ClinicalProfileField.condition => SchemaIds.conditionLabels[value],
    ClinicalProfileField.drugClass =>
      SchemaIds.drugClassLabels[_withoutClassPrefix(value)],
    ClinicalProfileField.goal =>
      SchemaIds.goalLabels[value] ?? _legacyGoalLabels[value],
    ClinicalProfileField.allergen =>
      SchemaIds.allergenLabels[value] ??
          SchemaIds.allergenLabels['ALLERGEN_${value.toUpperCase()}'],
  };
  if (knownLabel != null) return knownLabel;

  return _humanizeIdentifier(value);
}

const _legacyGoalLabels = <String, String>{
  'sleep': 'Sleep Quality',
  'heart_health': 'Cardiovascular/Heart Health',
};

String _withoutClassPrefix(String value) {
  return value.startsWith('class:') ? value.substring('class:'.length) : value;
}

String _humanizeIdentifier(String value) {
  var normalized = _withoutClassPrefix(value);
  for (final prefix in const ['GOAL_', 'ALLERGEN_']) {
    if (normalized.startsWith(prefix)) {
      normalized = normalized.substring(prefix.length);
      break;
    }
  }

  return normalized
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map(_humanizeWord)
      .join(' ');
}

String _humanizeWord(String word) {
  const acronyms = {
    'ace': 'ACE',
    'arb': 'ARB',
    'hiv': 'HIV',
    'maoi': 'MAOI',
    'nsaid': 'NSAID',
    'ssri': 'SSRI',
    'snri': 'SNRI',
    'ttc': 'TTC',
  };
  final lower = word.toLowerCase();
  final acronym = acronyms[lower];
  if (acronym != null) return acronym;
  return '${lower[0].toUpperCase()}${lower.substring(1)}';
}
