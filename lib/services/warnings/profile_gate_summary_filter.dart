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

import 'package:pharmaguide/features/product_detail/widgets/interaction_warnings.dart';
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart';

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

    final anyFires = relevant.any(
      (w) => w.matchesProfile(
        userConditions: userProfile.conditions,
        userDrugClasses: userProfile.drugClasses,
        userProfileFlags: userProfile.profileFlags,
        productForm: productContext.productForm,
        nutrientForm: productContext.nutrientForm,
        dosePerDay: productContext.dosePerDay,
      ),
    );
    if (anyFires) {
      out[conditionId] = entry.value;
    }
    // else: every backing warning is gated off — drop the aggregation.
  }
  return out;
}

/// Filter `drug_class_summary` the same way, keyed on `drug_class_id`.
Map<String, dynamic> filterDrugClassSummaryByProfileGate({
  required Map<String, dynamic> drugClassSummary,
  required List<InteractionWarning> warnings,
  required UserProfile userProfile,
  required ProductContext productContext,
}) {
  if (drugClassSummary.isEmpty) return const <String, dynamic>{};

  final out = <String, dynamic>{};
  for (final entry in drugClassSummary.entries) {
    final drugClassId = entry.key;
    final relevant = warnings.where(
      (w) => w.drugClassIds.contains(drugClassId),
    );

    if (relevant.isEmpty) continue;

    final anyFires = relevant.any(
      (w) => w.matchesProfile(
        userConditions: userProfile.conditions,
        userDrugClasses: userProfile.drugClasses,
        userProfileFlags: userProfile.profileFlags,
        productForm: productContext.productForm,
        nutrientForm: productContext.nutrientForm,
        dosePerDay: productContext.dosePerDay,
      ),
    );
    if (anyFires) {
      out[drugClassId] = entry.value;
    }
  }
  return out;
}
