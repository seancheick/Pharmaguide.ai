import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The clinical-signal families the app produces today. New families
/// (allergen, recall, product_change) are added when their producers exist —
/// not before (no speculative enum members).
enum SignalFamily {
  /// InteractionResult — curated pairwise + the STACK_* heuristics.
  pairwiseInteraction,

  /// MedicationProfileWarning — a user medication × profile-gate rule.
  medicationProfile,

  /// DepletionMatch — a medication → depleted-nutrient relationship.
  medicationNutrient,

  /// NutrientStatus — a nutrient's cumulative stack exposure vs its UL.
  cumulativeExposure,
}

String _norm(String s) => s.trim().toLowerCase();

/// Deterministic, stable signal identity (execution brief §3.1).
///
/// Hashes ONLY identity inputs — never severity, copy, list order, timestamp,
/// catalog version, or (for cumulative exposure) the contributing products — so
/// a signal keeps its id across re-evaluation, stack reordering, and
/// copy/threshold updates. That stable id is what lets the lifecycle layer track
/// a concern as new → ongoing → changed → resolved.
///
/// Per-family recipe:
///   - pairwiseInteraction / medicationProfile / medicationNutrient:
///       sha256(family | sourceRuleId | sorted(normalized subjectIds))
///     `sourceRuleId` is the PERMANENT rule identity (never a revision), so an
///     evidence/threshold update surfaces as a `changed` on the SAME signal.
///   - cumulativeExposure:
///       sha256(family | nutrientId)   — deliberately NOT the products, so the
///     signal survives products being added/removed from the stack.
String deriveSignalId({
  required SignalFamily family,
  String? sourceRuleId,
  List<String> subjectIds = const [],
  String? nutrientId,
}) {
  final String key;
  switch (family) {
    case SignalFamily.cumulativeExposure:
      if (nutrientId == null || nutrientId.trim().isEmpty) {
        throw ArgumentError('cumulativeExposure signal id requires a nutrientId');
      }
      key = 'cumulativeExposure|${_norm(nutrientId)}';
    case SignalFamily.pairwiseInteraction:
    case SignalFamily.medicationProfile:
    case SignalFamily.medicationNutrient:
      if (sourceRuleId == null || sourceRuleId.trim().isEmpty) {
        throw ArgumentError('${family.name} signal id requires a sourceRuleId');
      }
      final subjects = subjectIds.map(_norm).where((s) => s.isNotEmpty).toList()
        ..sort();
      key = '${family.name}|${_norm(sourceRuleId)}|${subjects.join(',')}';
  }
  return sha256.convert(utf8.encode(key)).toString();
}
