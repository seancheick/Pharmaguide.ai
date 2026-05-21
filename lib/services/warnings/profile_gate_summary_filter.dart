// Profile-gate-aware filter for condition_summary / drug_class_summary
// aggregations.
//
// The pipeline emits two parallel surfaces in each detail blob:
//   1. `warnings[]` — per-rule entries, each carrying a `profile_gate`
//      that consumers (Flutter, Python tests) MUST evaluate against
//      (user_profile, product_context) before firing.
//   2. `interaction_summary.condition_summary` / `drug_class_summary` —
//      pipeline-side aggregation roll-ups of which conditions/drug-classes
//      have ANY rule firing for the product. NO profile_gate is attached
//      to these aggregations — they are computed before the pipeline
//      knows the user.
//
// Naive consumers (Fit Score, E2c medical compatibility) read the
// aggregation surface directly, computing penalties from
// condition_summary[id].highest_severity. That bypasses the per-warning
// profile_gate, producing a cross-surface inconsistency: the product
// detail page correctly suppresses a topical-aloe pregnancy alert via
// excludes.product_forms_any, but Fit Score still penalizes the product
// because condition_summary['pregnancy'] still exists.
//
// This module gates the aggregation surface against the warnings list,
// dropping condition/drug-class entries whose underlying gated warnings
// no longer fire for the active (user_profile, product_context). The
// result is a filtered summary that callers feed into their existing
// penalty/score logic without further changes.
//
// Reuses lib/services/warnings/profile_gate_evaluator.dart — does NOT
// duplicate the gate evaluator.

import 'package:pharmaguide/services/warnings/interaction_warning.dart';
import 'package:pharmaguide/services/health/product_health_facts.dart';
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart';

typedef ProductContextForWarning =
    ProductContext Function(InteractionWarning warning);

ProductContext resolveProfileGateProductContext({
  required Map<String, dynamic>? detailBlob,
  required InteractionWarning warning,
  ProductHealthFacts? healthFacts,
  String? productForm,
}) {
  final facts =
      healthFacts ??
      (detailBlob == null
          ? null
          : ProductHealthFacts.fromDetailBlob(detailBlob));
  final ingredient = _findIngredientForWarning(facts, warning);
  return ProductContext(
    productForm: _normalizeProductForm(
      _stringValue(productForm) ?? facts?.productForm,
    ),
    nutrientForm: _nutrientFormForIngredient(ingredient),
    dosePerDay: _dosePerDayForIngredient(ingredient),
  );
}

/// Filter `condition_summary` against the per-warning profile_gate evaluator.
///
/// For each entry in [conditionSummary], inspect the warnings tagged with
/// the same `condition_id`. The entry survives if AT LEAST ONE such
/// warning fires (`matchesProfile` returns true) for the active
/// [userProfile] + [productContext]. If zero warnings reference the
/// condition, the entry is also dropped — without backing evidence we
/// will not penalize.
///
/// Returns a NEW map; never mutates the input.
Map<String, dynamic> filterConditionSummaryByProfileGate({
  required Map<String, dynamic> conditionSummary,
  required List<InteractionWarning> warnings,
  required UserProfile userProfile,
  required ProductContext productContext,
  ProductContextForWarning? productContextForWarning,
}) {
  if (conditionSummary.isEmpty) return const <String, dynamic>{};

  final out = <String, dynamic>{};
  for (final entry in conditionSummary.entries) {
    final conditionId = entry.key;
    final relevant = warnings.where(
      (w) => w.conditionIds.contains(conditionId),
    );

    if (relevant.isEmpty) {
      // No backing warning at all. Stale aggregation — drop. Without
      // a per-warning gate to consult, we have no evidence the product
      // really triggers this condition. Failing closed protects users
      // from false penalties.
      continue;
    }

    final anyFires = relevant.any((w) {
      final context = productContextForWarning?.call(w) ?? productContext;
      return w.matchesProfile(
        userConditions: userProfile.conditions,
        userDrugClasses: userProfile.drugClasses,
        userProfileFlags: userProfile.profileFlags,
        productForm: context.productForm,
        nutrientForm: context.nutrientForm,
        dosePerDay: context.dosePerDay,
      );
    });
    if (anyFires) {
      out[conditionId] = entry.value;
    }
    // else: every backing warning is gated off — drop the aggregation.
  }
  return out;
}

Map<String, dynamic>? _findIngredientForWarning(
  ProductHealthFacts? facts,
  InteractionWarning warning,
) {
  if (facts == null) return null;
  final target = _contextKey(warning.ingredientName ?? '');
  if (target.isEmpty) return null;

  final candidates = facts.ingredientContextRows;

  final exact = candidates
      .where((row) {
        return _ingredientKeys(row).contains(target);
      })
      .toList(growable: false);
  if (exact.isNotEmpty) return exact.first;

  for (final row in candidates) {
    for (final key in _ingredientKeys(row)) {
      if (key.length >= 4 &&
          target.length >= 4 &&
          (key.contains(target) || target.contains(key))) {
        return row;
      }
    }
  }
  return null;
}

Set<String> _ingredientKeys(Map<String, dynamic> row) {
  final keys = <String>{};
  for (final field in const [
    'name',
    'standard_name',
    'standardName',
    'display_label',
    'raw_source_text',
    'ingredient',
    'canonical_id',
    'normalized_key',
  ]) {
    final key = _contextKey(_stringValue(row[field]) ?? '');
    if (key.isNotEmpty) keys.add(key);
  }
  return keys;
}

String? _nutrientFormForIngredient(Map<String, dynamic>? row) {
  if (row == null) return null;
  for (final field in const [
    'nutrient_form',
    'form_detected',
    'matched_form',
    'display_form_label',
  ]) {
    final normalized = _normalizeNutrientForm(_stringValue(row[field]));
    if (normalized != null) return normalized;
  }

  final matchedForms = row['matched_forms'];
  if (matchedForms is List) {
    for (final entry in matchedForms.whereType<Map<Object?, Object?>>()) {
      for (final field in const [
        'form_key',
        'raw_form_text',
        'matched_candidate',
      ]) {
        final normalized = _normalizeNutrientForm(_stringValue(entry[field]));
        if (normalized != null) return normalized;
      }
    }
  }

  final extractedForms = row['extracted_forms'];
  if (extractedForms is List) {
    for (final entry in extractedForms.whereType<Map<Object?, Object?>>()) {
      for (final field in const ['display_form', 'raw_form_text']) {
        final normalized = _normalizeNutrientForm(_stringValue(entry[field]));
        if (normalized != null) return normalized;
      }
    }
  }

  return null;
}

num? _dosePerDayForIngredient(Map<String, dynamic>? row) {
  if (row == null) return null;
  for (final field in const [
    'per_day_mid',
    'per_day_max',
    'converted_quantity',
    'dosage',
    'quantity',
    'normalized_amount',
    'normalizedAmount',
  ]) {
    final value = _numValue(row[field]);
    if (value != null) return value;
  }
  return null;
}

String? _normalizeProductForm(String? raw) {
  final value = raw?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  final isTopical = RegExp(
    r'\b(topical|cream|ointment|lotion|transdermal)\b',
  ).hasMatch(value);
  if (isTopical) return 'topical_only';
  if (value.contains('softgel') ||
      value.contains('capsule') ||
      value.contains('caplet')) {
    return 'capsule';
  }
  if (value.contains('tablet')) return 'tablet';
  if (value.contains('powder')) return 'powder';
  if (value.contains('liquid') ||
      value.contains('drop') ||
      value.contains('tincture')) {
    return 'liquid_oral';
  }
  return _contextKey(value);
}

String? _normalizeNutrientForm(String? raw) {
  final value = raw?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  if (value.contains('beta') && value.contains('carotene')) {
    return 'beta_carotene';
  }
  if (value.contains('mixed') && value.contains('carotenoid')) {
    return 'mixed_carotenoids';
  }
  if (value.contains('retinol') || value.contains('retinyl')) {
    return 'retinol';
  }
  return _contextKey(value);
}

String? _stringValue(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

num? _numValue(Object? raw) {
  if (raw is num) return raw;
  if (raw is String) return num.tryParse(raw.trim());
  return null;
}

String _contextKey(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

/// Filter `drug_class_summary` the same way, keyed on `drug_class_id`.
Map<String, dynamic> filterDrugClassSummaryByProfileGate({
  required Map<String, dynamic> drugClassSummary,
  required List<InteractionWarning> warnings,
  required UserProfile userProfile,
  required ProductContext productContext,
  ProductContextForWarning? productContextForWarning,
}) {
  if (drugClassSummary.isEmpty) return const <String, dynamic>{};

  final out = <String, dynamic>{};
  for (final entry in drugClassSummary.entries) {
    final drugClassId = entry.key;
    final relevant = warnings.where(
      (w) => w.drugClassIds.contains(drugClassId),
    );

    if (relevant.isEmpty) continue;

    final anyFires = relevant.any((w) {
      final context = productContextForWarning?.call(w) ?? productContext;
      return w.matchesProfile(
        userConditions: userProfile.conditions,
        userDrugClasses: userProfile.drugClasses,
        userProfileFlags: userProfile.profileFlags,
        productForm: context.productForm,
        nutrientForm: context.nutrientForm,
        dosePerDay: context.dosePerDay,
      );
    });
    if (anyFires) {
      out[drugClassId] = entry.value;
    }
  }
  return out;
}
