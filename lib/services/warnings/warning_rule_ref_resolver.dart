// Schema-3 warning-reference resolution.
//
// The pipeline owns the projection algorithm in `scripts/export_schema.py`.
// Keep this reconstruction byte-for-byte equivalent at the map level so a
// catalog schema change cannot alter the warning a user sees.

import 'dart:convert';

import 'package:crypto/crypto.dart';

List<Map<String, dynamic>> warningRuleRefs(Map<String, dynamic>? blob) {
  final raw = blob?['warning_rule_refs'];
  if (raw == null) return const <Map<String, dynamic>>[];
  if (raw is! List) {
    throw const FormatException('warning_rule_refs must be a list');
  }
  return raw
      .map((item) {
        if (item is! Map) {
          throw const FormatException(
            'warning_rule_refs entries must be objects',
          );
        }
        return Map<String, dynamic>.from(item);
      })
      .toList(growable: false);
}

Set<String> warningRuleIds(Map<String, dynamic>? blob) {
  return warningRuleRefs(blob).map((ref) {
    final id = ref['rule_id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const FormatException('warning rule ref is missing rule_id');
    }
    return id;
  }).toSet();
}

List<String> _normalizedIds(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, dynamic> _subentryCopy(
  Map<String, dynamic> subentry,
  String subentryKind,
) {
  final actionKey = subentryKind == 'pregnancy_lactation' ? 'notes' : 'action';
  return <String, dynamic>{
    'detail': _pythonStringOrEmpty(subentry['mechanism']),
    'action': _pythonStringOrEmpty(subentry[actionKey]),
    'alert_headline': subentry['alert_headline'],
    'alert_body': subentry['alert_body'],
    'informational_note': subentry['informational_note'],
  };
}

String _warningCopyFingerprint(Map<String, dynamic> copyFields) {
  // Python's json.dumps(..., sort_keys=True, separators=(',', ':')) emits
  // these five keys in this exact lexical order. Dart maps preserve insertion
  // order and jsonEncode already uses compact separators.
  final canonical = <String, dynamic>{
    'action': copyFields['action'],
    'alert_body': copyFields['alert_body'],
    'alert_headline': copyFields['alert_headline'],
    'detail': copyFields['detail'],
    'informational_note': copyFields['informational_note'],
  };
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

List<({Map<String, dynamic> subentry, String kind})> _candidateSubentries(
  Map<String, dynamic> rule,
  Map<String, dynamic> ref,
) {
  final conditionIds = _normalizedIds(ref['condition_ids']);
  final drugClassIds = _normalizedIds(ref['drug_class_ids']);
  final candidates = <({Map<String, dynamic> subentry, String kind})>[];
  if (conditionIds.isNotEmpty) {
    final target = conditionIds.first;
    final conditionRules = rule['condition_rules'];
    if (conditionRules is List) {
      for (final candidate in conditionRules) {
        if (candidate is Map &&
            candidate['condition_id']?.toString().trim() == target) {
          candidates.add((
            subentry: Map<String, dynamic>.from(candidate),
            kind: 'condition',
          ));
        }
      }
    }
    final pregnancyLactation = rule['pregnancy_lactation'];
    if (const {'pregnancy', 'lactation'}.contains(target) &&
        pregnancyLactation is Map) {
      candidates.add((
        subentry: Map<String, dynamic>.from(pregnancyLactation),
        kind: 'pregnancy_lactation',
      ));
    }
  }
  if (drugClassIds.isNotEmpty) {
    final target = drugClassIds.first;
    final drugClassRules = rule['drug_class_rules'];
    if (drugClassRules is List) {
      for (final candidate in drugClassRules) {
        if (candidate is Map &&
            candidate['drug_class_id']?.toString().trim() == target) {
          candidates.add((
            subentry: Map<String, dynamic>.from(candidate),
            kind: 'drug_class',
          ));
        }
      }
    }
  }
  return candidates;
}

({Map<String, dynamic> subentry, String kind}) _ruleSubentry(
  Map<String, dynamic> rule,
  Map<String, dynamic> ref,
) {
  final copyFingerprint = ref['copy_fingerprint']?.toString().trim() ?? '';
  if (copyFingerprint.isEmpty) {
    throw FormatException(
      'warning rule ref ${ref['rule_id']} is missing copy_fingerprint',
    );
  }
  for (final candidate in _candidateSubentries(rule, ref)) {
    if (_warningCopyFingerprint(
          _subentryCopy(candidate.subentry, candidate.kind),
        ) ==
        copyFingerprint) {
      return candidate;
    }
  }
  throw FormatException(
    'warning rule ref ${ref['rule_id']} has no matching reviewed copy',
  );
}

Object? _refOrRuleValue(
  Map<String, dynamic> ref,
  Map<String, dynamic> subentry,
  String key,
) => ref.containsKey(key) ? ref[key] : subentry[key];

Object? _firstNonEmpty(Object? preferred, Object? fallback) {
  return _isPythonFalsy(preferred) ? fallback : preferred;
}

bool _isPythonFalsy(Object? value) =>
    value == null ||
    value == false ||
    value == 0 ||
    (value is String && value.isEmpty) ||
    (value is Iterable && value.isEmpty) ||
    (value is Map && value.isEmpty);

String _pythonStringOrEmpty(Object? value) =>
    _isPythonFalsy(value) ? '' : value.toString();

Map<String, dynamic> _resolvedWarning(
  Map<String, dynamic> ref,
  Map<String, dynamic> rule,
) {
  final selected = _ruleSubentry(rule, ref);
  final subentry = selected.subentry;
  final copyFields = _subentryCopy(subentry, selected.kind);
  final conditionIds = _normalizedIds(ref['condition_ids']);
  final drugClassIds = _normalizedIds(ref['drug_class_ids']);
  final ingredientName = _pythonStringOrEmpty(ref['ingredient_name']).trim();
  final scopeId = conditionIds.isNotEmpty
      ? conditionIds.first
      : (drugClassIds.isNotEmpty ? drugClassIds.first : '');
  final severity = _firstNonEmpty(ref['severity'], subentry['severity']);
  final type =
      _firstNonEmpty(ref['type'], null) ??
      (drugClassIds.isNotEmpty ? 'drug_interaction' : 'interaction');
  final evidenceLevel = _refOrRuleValue(ref, subentry, 'evidence_level');
  final sourceValue = _refOrRuleValue(ref, subentry, 'sources');

  final resolved = <String, dynamic>{
    'type': type,
    'severity': severity,
    'severity_contextual': ref['severity_contextual'],
    'display_mode_default': ref['display_mode_default'],
    'title': '$ingredientName / $scopeId',
    'detail': copyFields['detail'],
    'action': copyFields['action'],
    'alert_headline': copyFields['alert_headline'],
    'alert_body': copyFields['alert_body'],
    'informational_note': copyFields['informational_note'],
    'condition_ids': conditionIds,
    'drug_class_ids': drugClassIds,
    'ingredient_name': ingredientName,
    'ingredient_canonical_id': ref['ingredient_canonical_id'],
    'evidence_level': _pythonStringOrEmpty(evidenceLevel),
    'sources': sourceValue is List
        ? List<dynamic>.from(sourceValue)
        : <dynamic>[],
    'dose_threshold_evaluation': null,
    'dose_decision': ref['dose_decision'],
    'direction': ref.containsKey('direction')
        ? ref['direction']
        : subentry['direction'],
    'materiality': ref.containsKey('materiality')
        ? ref['materiality']
        : subentry['materiality'],
    'min_effective_dose': ref.containsKey('min_effective_dose')
        ? ref['min_effective_dose']
        : subentry['min_effective_dose'],
    'dose_floor_status': ref['dose_floor_status'],
    'source': 'interaction_rules',
    'source_rule_id': ref['rule_id']?.toString() ?? '',
    'profile_gate': ref.containsKey('profile_gate')
        ? ref['profile_gate']
        : subentry['profile_gate'],
  };
  if (ref.containsKey('source_producers')) {
    final producers = ref['source_producers'];
    resolved['source_producers'] = producers is List
        ? List<dynamic>.from(producers)
        : <dynamic>[];
  }
  return resolved;
}

List<Map<String, dynamic>> resolveWarningRuleRefs(
  Map<String, dynamic>? blob,
  Map<String, Map<String, dynamic>> rulesById,
) {
  final resolved = <Map<String, dynamic>>[];
  for (final ref in warningRuleRefs(blob)) {
    final ruleId = ref['rule_id']?.toString().trim() ?? '';
    final rule = rulesById[ruleId];
    if (rule == null) {
      throw FormatException(
        'warning rule ref cannot resolve rule_id="$ruleId"',
      );
    }
    resolved.add(_resolvedWarning(ref, rule));
  }
  return resolved;
}
