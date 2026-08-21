// Schema-3 warning-reference resolution.
//
// The pipeline owns the projection algorithm in `scripts/export_schema.py`.
// Keep this reconstruction byte-for-byte equivalent at the map level so a
// catalog schema change cannot alter the warning a user sees.

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

Map<String, dynamic> _ruleSubentry(
  Map<String, dynamic> rule,
  Map<String, dynamic> ref,
) {
  final conditionIds = _normalizedIds(ref['condition_ids']);
  final drugClassIds = _normalizedIds(ref['drug_class_ids']);
  if (conditionIds.isNotEmpty) {
    final target = conditionIds.first;
    final candidates = rule['condition_rules'];
    if (candidates is List) {
      for (final candidate in candidates) {
        if (candidate is Map &&
            candidate['condition_id']?.toString().trim() == target) {
          return Map<String, dynamic>.from(candidate);
        }
      }
    }
  }
  if (drugClassIds.isNotEmpty) {
    final target = drugClassIds.first;
    final candidates = rule['drug_class_rules'];
    if (candidates is List) {
      for (final candidate in candidates) {
        if (candidate is Map &&
            candidate['drug_class_id']?.toString().trim() == target) {
          return Map<String, dynamic>.from(candidate);
        }
      }
    }
  }
  throw FormatException(
    'warning rule ref ${ref['rule_id']} has no matching condition/drug sub-rule',
  );
}

Map<String, dynamic> _resolvedWarning(
  Map<String, dynamic> ref,
  Map<String, dynamic> rule,
) {
  final subentry = _ruleSubentry(rule, ref);
  final conditionIds = _normalizedIds(ref['condition_ids']);
  final drugClassIds = _normalizedIds(ref['drug_class_ids']);
  final ingredientName = ref['ingredient_name']?.toString().trim() ?? '';
  final scopeId = conditionIds.isNotEmpty
      ? conditionIds.first
      : (drugClassIds.isNotEmpty ? drugClassIds.first : '');
  final severity = ref['severity'] ?? subentry['severity'];
  final type =
      ref['type'] ??
      (drugClassIds.isNotEmpty ? 'drug_interaction' : 'interaction');

  return <String, dynamic>{
    'type': type,
    'severity': severity,
    'severity_contextual': ref['severity_contextual'],
    'display_mode_default': ref['display_mode_default'],
    'title': '$ingredientName / $scopeId',
    'detail': subentry['mechanism']?.toString() ?? '',
    'action': subentry['action']?.toString() ?? '',
    'alert_headline': subentry['alert_headline'],
    'alert_body': subentry['alert_body'],
    'informational_note': subentry['informational_note'],
    'condition_ids': conditionIds,
    'drug_class_ids': drugClassIds,
    'ingredient_name': ingredientName,
    'ingredient_canonical_id': ref['ingredient_canonical_id'],
    'evidence_level': subentry['evidence_level']?.toString() ?? '',
    'sources': subentry['sources'] is List
        ? List<dynamic>.from(subentry['sources'] as List)
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
