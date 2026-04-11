// StackNutrientModels — value types for the stack-level nutrient
// accumulator and UL checker (M1 of the interaction-and-safety
// feature).
//
// These types are intentionally dumb: no business logic, no async,
// no persistence. The aggregator and UL checker are pure functions
// that take these as input/output. That keeps the math testable and
// isolates it from the detail-blob fetch path.

import 'package:flutter/foundation.dart';

/// One product's contribution to the stack, as seen by the aggregator.
///
/// [ingredients] is the raw `detail_blob.ingredients` array from the
/// bundled catalog or Supabase detail-blob fetch. We do not copy or
/// reshape it — the aggregator reads defensively so schema drift in
/// the pipeline never crashes the app.
@immutable
class StackItemNutrients {
  const StackItemNutrients({
    required this.stackEntryId,
    required this.productName,
    required this.ingredients,
  });

  final String stackEntryId;
  final String productName;
  final List<Map<String, dynamic>> ingredients;
}

/// One product's contribution to a specific nutrient's running total.
@immutable
class NutrientContribution {
  const NutrientContribution({
    required this.stackEntryId,
    required this.productName,
    required this.amount,
    required this.unit,
  });

  final String stackEntryId;
  final String productName;
  final double amount;
  final String unit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NutrientContribution &&
          runtimeType == other.runtimeType &&
          stackEntryId == other.stackEntryId &&
          productName == other.productName &&
          amount == other.amount &&
          unit == other.unit;

  @override
  int get hashCode =>
      Object.hash(stackEntryId, productName, amount, unit);
}

/// Aggregated total for one nutrient across every stack item.
///
/// [hasUnitConflict] is true if two contributions reported the same
/// canonical nutrient in incompatible units (e.g., one in mg, one in
/// mcg). When that happens, only contributions matching the canonical
/// [unit] (the first one seen) are summed into [totalAmount]. The
/// conflicting contributions still appear in [contributions] so the
/// UI can surface them, but they are excluded from the sum to prevent
/// silent numeric errors.
@immutable
class NutrientTotal {
  const NutrientTotal({
    required this.canonicalId,
    required this.displayName,
    required this.totalAmount,
    required this.unit,
    required this.contributions,
    this.hasUnitConflict = false,
  });

  final String canonicalId;
  final String displayName;
  final double totalAmount;
  final String unit;
  final List<NutrientContribution> contributions;
  final bool hasUnitConflict;
}

/// Classification of a nutrient's stack-level exposure against RDA
/// and UL benchmarks.
///
/// Order matters — the UI sorts by this enum descending so the most
/// dangerous nutrients surface first.
enum NutrientTier {
  /// No RDA data exists for this nutrient — show raw amount only.
  noRda,

  /// Total is below 50% of RDA — informational, not flagged.
  underFifty,

  /// 50–100% of RDA — adequate.
  adequate,

  /// 100–200% of RDA — abundant but safe.
  abundant,

  /// >200% of RDA but <80% of UL — above typical, monitor.
  aboveTypical,

  /// 80–100% of UL — approaching the upper limit.
  approachingUl,

  /// >100% of UL — exceeds the upper limit, warning fires.
  exceedsUl,
}

/// Per-nutrient status produced by the UL checker.
@immutable
class NutrientStatus {
  const NutrientStatus({
    required this.total,
    required this.tier,
    this.rda,
    this.ul,
    this.pctOfRda,
    this.pctOfUl,
    this.warning,
  });

  final NutrientTotal total;
  final NutrientTier tier;
  final double? rda;
  final double? ul;
  final double? pctOfRda;
  final double? pctOfUl;
  final String? warning;

  /// True when this nutrient should surface a visible warning to the
  /// user. The caller decides whether to render it as a chip, a
  /// banner, or an inline message.
  bool get shouldWarn =>
      tier == NutrientTier.approachingUl || tier == NutrientTier.exceedsUl;
}
