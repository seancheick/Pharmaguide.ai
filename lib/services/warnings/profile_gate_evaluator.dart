// Dart implementation of the v6.0 profile_gate evaluator.
//
// MUST produce identical (fires, severity) output to the Python reference
// at `dsld_clean/scripts/profile_gate_evaluator.py` for every case in
// `dsld_clean/scripts/data/profile_gate_test_cases.json` (the shared
// drift-contract fixture).
//
// Semantics — locked by `dsld_clean/scripts/INTERACTION_RULE_SCHEMA_V6_ADR.md`:
//   * `requires`: AND across populated keys, OR within each list.
//   * `excludes`: OR — any match suppresses the rule.
//   * `dose`: optional severity modifier post-match. Does NOT affect fires.
//
// This file MUST stay in lockstep with the Python reference. Update both
// or you create drift.

import 'dart:core';

/// Allowed gate types — mirrors `ALLOWED_GATE_TYPES` in the Python ref.
const Set<String> _allowedGateTypes = {
  'condition',
  'drug_class',
  'profile_flag',
  'dose',
  'nutrient_form',
  'combination',
};

/// Per-gate-type single-axis allowance.
const Map<String, String> _gateTypeRequiredKey = {
  'condition': 'conditions_any',
  'drug_class': 'drug_classes_any',
  'profile_flag': 'profile_flags_any',
};

/// Result of evaluating a profile_gate.
class GateEvaluationResult {
  final bool fires;
  final String? severity;
  final String reason;

  const GateEvaluationResult({
    required this.fires,
    this.severity,
    this.reason = '',
  });

  @override
  String toString() =>
      'GateEvaluationResult(fires=$fires, severity=$severity, reason=$reason)';
}

/// User profile inputs — must mirror Python's `user_profile` dict shape.
class UserProfile {
  final Set<String> conditions;
  final Set<String> drugClasses;
  final Set<String> profileFlags;

  const UserProfile({
    this.conditions = const <String>{},
    this.drugClasses = const <String>{},
    this.profileFlags = const <String>{},
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        conditions: _toSet(json['conditions']),
        drugClasses: _toSet(json['drug_classes']),
        profileFlags: _toSet(json['profile_flags']),
      );

  static Set<String> _toSet(Object? raw) {
    if (raw is Iterable) {
      return raw.whereType<String>().toSet();
    }
    return const <String>{};
  }
}

/// Product context — must mirror Python's `product_context` dict shape.
class ProductContext {
  final String? productForm;
  final String? nutrientForm;
  final num? dosePerDay;
  final String? doseUnit;

  const ProductContext({
    this.productForm,
    this.nutrientForm,
    this.dosePerDay,
    this.doseUnit,
  });

  factory ProductContext.fromJson(Map<String, dynamic> json) => ProductContext(
        productForm: _str(json['product_form']),
        nutrientForm: _str(json['nutrient_form']),
        dosePerDay: json['dose_per_day'] is num
            ? json['dose_per_day'] as num
            : null,
        doseUnit: _str(json['dose_unit']),
      );

  static String? _str(Object? raw) =>
      raw is String && raw.isNotEmpty ? raw : null;
}

/// Evaluate whether a profile_gate fires for this user + product, and at
/// what severity.
///
/// MUST match `scripts/profile_gate_evaluator.py::evaluate_profile_gate`.
GateEvaluationResult evaluateProfileGate(
  Map<String, dynamic>? gate,
  UserProfile userProfile,
  ProductContext productContext, {
  String? baseSeverity,
}) {
  if (gate == null) {
    // Pre-v6.0 blob with no gate. Treat as "fires" (legacy passthrough).
    // Step 9 wiring should never call this with a null gate once v1.6.0
    // catalog DB is the only source.
    return GateEvaluationResult(
      fires: true,
      severity: baseSeverity,
      reason: 'no profile_gate (pre-v6.0 fallback)',
    );
  }

  final requires = _asMap(gate['requires']);
  final excludes = _asMap(gate['excludes']);

  // requires: AND across populated keys, OR within each list.
  final requirePairs = <(String, Set<String>)>[
    ('conditions_any', userProfile.conditions),
    ('drug_classes_any', userProfile.drugClasses),
    ('profile_flags_any', userProfile.profileFlags),
  ];

  for (final (key, userSet) in requirePairs) {
    final reqList = _asStringList(requires[key]);
    if (reqList.isNotEmpty && !reqList.any(userSet.contains)) {
      return GateEvaluationResult(
        fires: false,
        severity: null,
        reason: 'requires.$key not satisfied: needs any of $reqList, '
            'user has ${userSet.toList()..sort()}',
      );
    }
  }

  // excludes: OR — any match suppresses.
  for (final (key, userSet) in requirePairs) {
    final excList = _asStringList(excludes[key]);
    if (excList.isNotEmpty) {
      final overlap = excList.where(userSet.contains).toList();
      if (overlap.isNotEmpty) {
        return GateEvaluationResult(
          fires: false,
          severity: null,
          reason: 'excludes.$key suppressed: matched $overlap',
        );
      }
    }
  }

  final productForm = productContext.productForm;
  if (productForm != null &&
      _asStringList(excludes['product_forms_any']).contains(productForm)) {
    return GateEvaluationResult(
      fires: false,
      severity: null,
      reason: 'excludes.product_forms_any suppressed: '
          'product_form="$productForm"',
    );
  }

  final nutrientForm = productContext.nutrientForm;
  if (nutrientForm != null &&
      _asStringList(excludes['nutrient_forms_any']).contains(nutrientForm)) {
    return GateEvaluationResult(
      fires: false,
      severity: null,
      reason: 'excludes.nutrient_forms_any suppressed: '
          'nutrient_form="$nutrientForm"',
    );
  }

  // Gate matched. Compute severity.
  String? severity = baseSeverity;
  final dose = gate['dose'];
  if (dose is Map<String, dynamic>) {
    final resolved = _resolveDoseSeverity(dose, productContext);
    if (resolved != null) {
      severity = resolved;
    }
  }

  return GateEvaluationResult(
    fires: true,
    severity: severity,
    reason: 'all gate predicates satisfied',
  );
}

/// Validator — mirrors Python's `validate_profile_gate`. Returns a list of
/// error strings (empty list = valid).
List<String> validateProfileGate(
  Map<String, dynamic>? gate, {
  Map<String, dynamic>? taxonomy,
}) {
  if (gate == null) return ['profile_gate is null'];

  final errors = <String>[];
  final gt = gate['gate_type'];
  if (gt is! String || !_allowedGateTypes.contains(gt)) {
    errors.add('gate_type ${gt is String ? '"$gt"' : '$gt'} '
        'not in $_allowedGateTypes');
  }

  final requires = _asMap(gate['requires']);
  final excludes = _asMap(gate['excludes']);

  for (final k in const ['conditions_any', 'drug_classes_any', 'profile_flags_any']) {
    if (!requires.containsKey(k)) {
      errors.add('requires missing key "$k"');
    } else {
      for (final v in _asStringList(requires[k])) {
        if (v.trim().isEmpty) {
          errors.add('requires.$k contains empty/whitespace id');
        }
      }
    }
  }

  for (final k in const [
    'conditions_any',
    'drug_classes_any',
    'profile_flags_any',
    'product_forms_any',
    'nutrient_forms_any',
  ]) {
    if (!excludes.containsKey(k)) {
      errors.add('excludes missing key "$k"');
    }
  }

  // Per-gate-type strict-key check.
  if (gt is String && _gateTypeRequiredKey.containsKey(gt)) {
    final required = _gateTypeRequiredKey[gt]!;
    if (_asStringList(requires[required]).isEmpty) {
      errors.add('gate_type="$gt" requires non-empty requires.$required');
    }
    for (final k in const ['conditions_any', 'drug_classes_any', 'profile_flags_any']) {
      if (k != required && _asStringList(requires[k]).isNotEmpty) {
        errors.add('gate_type="$gt" must only populate requires.$required; '
            'found requires.$k populated (use gate_type="combination")');
      }
    }
  } else if (gt == 'combination') {
    final populated = ['conditions_any', 'drug_classes_any', 'profile_flags_any']
        .where((k) => _asStringList(requires[k]).isNotEmpty)
        .length;
    final hasDose = gate['dose'] is Map;
    if (populated < 2 && !hasDose) {
      errors.add('gate_type="combination" needs ≥2 populated requires keys '
          'OR a dose block; got requires_populated=$populated dose=absent');
    }
  } else if (gt == 'dose') {
    if (gate['dose'] is! Map) {
      errors.add('gate_type="dose" requires non-null dose block');
    }
  }

  // Cross-vocabulary check.
  if (taxonomy != null) {
    final validConditions = _idSet(taxonomy['conditions']);
    final validDrugClasses = _idSet(taxonomy['drug_classes']);
    final validFlags = _idSet(taxonomy['profile_flags']);
    final validProductForms = _idSet(taxonomy['product_forms']);

    for (final v in [
      ..._asStringList(requires['conditions_any']),
      ..._asStringList(excludes['conditions_any']),
    ]) {
      if (v.isNotEmpty && !validConditions.contains(v)) {
        errors.add('unknown condition_id "$v" (not in taxonomy.conditions)');
      }
    }
    for (final v in [
      ..._asStringList(requires['drug_classes_any']),
      ..._asStringList(excludes['drug_classes_any']),
    ]) {
      if (v.isNotEmpty && !validDrugClasses.contains(v)) {
        errors.add('unknown drug_class_id "$v" (not in taxonomy.drug_classes)');
      }
    }
    for (final v in [
      ..._asStringList(requires['profile_flags_any']),
      ..._asStringList(excludes['profile_flags_any']),
    ]) {
      if (v.isNotEmpty && !validFlags.contains(v)) {
        errors.add('unknown profile_flag "$v" (not in taxonomy.profile_flags)');
      }
    }
    for (final v in _asStringList(excludes['product_forms_any'])) {
      if (v.isNotEmpty && !validProductForms.contains(v)) {
        errors.add('unknown product_form "$v" (not in taxonomy.product_forms)');
      }
    }
  }

  return errors;
}

// --- Helpers ---

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
  return const <String, dynamic>{};
}

List<String> _asStringList(Object? raw) {
  if (raw is Iterable) {
    return raw.whereType<String>().toList();
  }
  return const <String>[];
}

Set<String> _idSet(Object? raw) {
  if (raw is Iterable) {
    return raw
        .whereType<Map<String, dynamic>>()
        .map((m) => m['id']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
  }
  return const <String>{};
}

String? _resolveDoseSeverity(
  Map<String, dynamic> dose,
  ProductContext context,
) {
  final comparator = dose['comparator'];
  final threshold = dose['value'];
  final userDose = context.dosePerDay;

  if (userDose == null || threshold is! num || comparator is! String) {
    return dose['severity_if_not_met'] as String?;
  }

  final u = userDose.toDouble();
  final t = threshold.toDouble();

  bool met;
  switch (comparator) {
    case '>':
      met = u > t;
      break;
    case '>=':
      met = u >= t;
      break;
    case '<':
      met = u < t;
      break;
    case '<=':
      met = u <= t;
      break;
    case '==':
      met = u == t;
      break;
    default:
      return dose['severity_if_not_met'] as String?;
  }

  return met
      ? dose['severity_if_met'] as String?
      : dose['severity_if_not_met'] as String?;
}
