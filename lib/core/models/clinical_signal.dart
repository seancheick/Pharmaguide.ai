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

/// Namespace + version prefix for every signal's canonical identity. Bump the
/// version ONLY on an intentional, breaking change to the id recipe.
const String signalIdNamespace = 'pg_signal:v1';

/// Normalize a subject / nutrient token for identity — case- and
/// whitespace-insensitive, so 'Warfarin' and ' warfarin ' collapse.
String normalizeSignalSubject(String s) => s.trim().toLowerCase();

/// The debug-readable canonical identity string, hashed by [deriveSignalId].
/// Retaining this pre-hash form makes lifecycle/diff diagnostics legible, e.g.
/// `pg_signal:v1:cumulativeExposure:vitamin_d`.
///
/// Per-family recipe (execution brief §3.1) — identity inputs ONLY, never
/// severity, copy, list order, timestamp, or catalog version:
///   - pairwiseInteraction / medicationProfile / medicationNutrient:
///       namespace : family : sourceRuleId : sorted(normalized subjectIds)
///     `sourceRuleId` is the PERMANENT rule identity (never a revision), so an
///     evidence/threshold update surfaces as a `changed` on the SAME signal.
///   - cumulativeExposure:
///       namespace : family : nutrientId   — deliberately NOT the products, so
///     the signal survives products being added to / removed from the stack.
String canonicalSignalId({
  required SignalFamily family,
  String? sourceRuleId,
  List<String> subjectIds = const [],
  String? nutrientId,
}) {
  switch (family) {
    case SignalFamily.cumulativeExposure:
      if (nutrientId == null || nutrientId.trim().isEmpty) {
        throw ArgumentError('cumulativeExposure signal id requires a nutrientId');
      }
      return '$signalIdNamespace:${family.name}:'
          '${normalizeSignalSubject(nutrientId)}';
    case SignalFamily.pairwiseInteraction:
    case SignalFamily.medicationProfile:
    case SignalFamily.medicationNutrient:
      if (sourceRuleId == null || sourceRuleId.trim().isEmpty) {
        throw ArgumentError('${family.name} signal id requires a sourceRuleId');
      }
      final subjects = subjectIds
          .map(normalizeSignalSubject)
          .where((s) => s.isNotEmpty)
          .toList()
        ..sort();
      return '$signalIdNamespace:${family.name}:'
          '${normalizeSignalSubject(sourceRuleId)}:${subjects.join(',')}';
  }
}

/// Deterministic, stable signal id — sha256 of [canonicalSignalId]. The stable
/// id is what lets the lifecycle layer track a concern as
/// new → ongoing → changed → resolved.
String deriveSignalId({
  required SignalFamily family,
  String? sourceRuleId,
  List<String> subjectIds = const [],
  String? nutrientId,
}) {
  final canonical = canonicalSignalId(
    family: family,
    sourceRuleId: sourceRuleId,
    subjectIds: subjectIds,
    nutrientId: nutrientId,
  );
  return sha256.convert(utf8.encode(canonical)).toString();
}
