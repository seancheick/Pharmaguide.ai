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

  /// StackDoseThresholdAlert — a profile-specific cumulative dose rule.
  doseThreshold,

  /// TimingOptimization — a verified `important_separation` rule.
  ///
  /// Only this timing category becomes a signal. Losing levothyroxine
  /// absorption is a safety concern, not the optimization advice the other two
  /// timing categories carry.
  timingSeparation,

  /// A human-approved post-purchase regulatory event matched to a product.
  regulatorySafety,
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
///   - doseThreshold:
///       namespace : family : target type/id : nutrient : comparator :
///       normalized threshold/unit.
String canonicalSignalId({
  required SignalFamily family,
  String? sourceRuleId,
  List<String> subjectIds = const [],
  String? nutrientId,
  String? targetType,
  String? targetId,
  String? comparator,
  double? thresholdValue,
  String? thresholdUnit,
}) {
  switch (family) {
    case SignalFamily.cumulativeExposure:
      if (nutrientId == null || nutrientId.trim().isEmpty) {
        throw ArgumentError(
          'cumulativeExposure signal id requires a nutrientId',
        );
      }
      return '$signalIdNamespace:${family.name}:'
          '${normalizeSignalSubject(nutrientId)}';
    case SignalFamily.doseThreshold:
      if (targetType == null ||
          targetType.trim().isEmpty ||
          targetId == null ||
          targetId.trim().isEmpty ||
          nutrientId == null ||
          nutrientId.trim().isEmpty ||
          comparator == null ||
          comparator.trim().isEmpty ||
          thresholdValue == null ||
          thresholdUnit == null ||
          thresholdUnit.trim().isEmpty) {
        throw ArgumentError(
          'doseThreshold signal id requires target, nutrient, comparator, '
          'threshold, and unit',
        );
      }
      return '$signalIdNamespace:${family.name}:'
          '${normalizeSignalSubject(targetType)}:'
          '${normalizeSignalSubject(targetId)}:'
          '${normalizeSignalSubject(nutrientId)}:'
          '${comparator.trim()}:'
          '${_canonicalNumber(thresholdValue)}:'
          '${normalizeSignalSubject(thresholdUnit)}';
    case SignalFamily.pairwiseInteraction:
    case SignalFamily.medicationProfile:
    case SignalFamily.medicationNutrient:
    case SignalFamily.timingSeparation:
    case SignalFamily.regulatorySafety:
      if (sourceRuleId == null || sourceRuleId.trim().isEmpty) {
        throw ArgumentError('${family.name} signal id requires a sourceRuleId');
      }
      final subjects =
          subjectIds
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
  String? targetType,
  String? targetId,
  String? comparator,
  double? thresholdValue,
  String? thresholdUnit,
}) {
  final canonical = canonicalSignalId(
    family: family,
    sourceRuleId: sourceRuleId,
    subjectIds: subjectIds,
    nutrientId: nutrientId,
    targetType: targetType,
    targetId: targetId,
    comparator: comparator,
    thresholdValue: thresholdValue,
    thresholdUnit: thresholdUnit,
  );
  return sha256.convert(utf8.encode(canonical)).toString();
}

String _canonicalNumber(double value) {
  if (value == value.truncateToDouble()) return value.toInt().toString();
  return value.toString();
}
