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
    this.ingredientName = '',
    required this.amount,
    this.minimumAmount,
    required this.unit,
  });

  final String stackEntryId;
  final String productName;
  final String ingredientName;

  /// Maximum daily contribution used for safety/UL comparisons.
  final double amount;

  /// Minimum/recommended daily contribution used for RDA/AI adequacy.
  /// Null on legacy fixed-dose rows, where [amount] serves both purposes.
  final double? minimumAmount;
  final String unit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NutrientContribution &&
          runtimeType == other.runtimeType &&
          stackEntryId == other.stackEntryId &&
          productName == other.productName &&
          ingredientName == other.ingredientName &&
          amount == other.amount &&
          minimumAmount == other.minimumAmount &&
          unit == other.unit;

  @override
  int get hashCode => Object.hash(
    stackEntryId,
    productName,
    ingredientName,
    amount,
    minimumAmount,
    unit,
  );
}

/// Why a disclosed stack contribution was excluded from RDA/UL math.
///
/// The contribution still remains visible so users can trace the product,
/// but the numeric value is not included in [NutrientTotal.totalAmount].
enum NutrientExclusionReason {
  missingUnit,
  notProvidedUnit,
  unsupportedUnit,
  unitConflict,
  skippedByPipeline,

  /// Within a single product, this row is a compound-form duplicate of a
  /// bare elemental row for the same canonical nutrient (e.g. 'Magnesium
  /// Glycinate 400 mg' alongside 'Magnesium 60 mg'). The elemental row is
  /// the label-declared total; summing the compound weight on top
  /// double-counts (compound weight includes the non-mineral moiety).
  compoundFormDuplicate,

  /// A legacy label blob emitted both a declared nutrient total and a
  /// form-specific re-derivation of that same total. The declared total is
  /// retained because it is the quantity printed on the Supplement Facts
  /// panel; the re-derived row stays traceable but must not be summed twice.
  declaredTotalDuplicate,
}

@immutable
class ExcludedNutrientContribution {
  const ExcludedNutrientContribution({
    required this.contribution,
    required this.reason,
  });

  final NutrientContribution contribution;
  final NutrientExclusionReason reason;
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
    this.minimumTotalAmount,
    required this.unit,
    required this.contributions,
    this.hasUnitConflict = false,
    this.excludedContributions = const [],
  });

  final String canonicalId;
  final String displayName;

  /// Maximum daily stack exposure used for safety/UL comparisons.
  final double totalAmount;

  /// Minimum/recommended daily stack exposure used for RDA/AI adequacy.
  /// Null on legacy fixed-dose totals, where [totalAmount] serves both.
  final double? minimumTotalAmount;
  final String unit;
  final List<NutrientContribution> contributions;
  final bool hasUnitConflict;
  final List<ExcludedNutrientContribution> excludedContributions;

  bool get hasExcludedContributions => excludedContributions.isNotEmpty;

  double get adequacyAmount => minimumTotalAmount ?? totalAmount;

  bool get hasDoseRange =>
      minimumTotalAmount != null &&
      (minimumTotalAmount! - totalAmount).abs() > 0.000001;
}

/// Classification of a nutrient's stack-level exposure against intake-target
/// and UL benchmarks.
///
/// Order matters — the UI sorts by this enum descending so the most
/// dangerous nutrients surface first.
enum NutrientTier {
  /// No RDA data exists for this nutrient — show raw amount only.
  noRda,

  /// Total is below 50% of the intake target — informational, not flagged.
  underFifty,

  /// 50–100% of the intake target — adequate.
  adequate,

  /// ≥100% of the intake target for a nutrient with NO established UL
  /// (vitamin K, B12, biotin, omega-3, CoQ10, potassium, etc.). High intake
  /// here is benign — there is no ceiling to approach — so it renders as a
  /// calm "above adequate" state, never the amber abundant/aboveTypical
  /// warning tiers, which are reserved for UL-bounded nutrients. Placed just
  /// above [adequate] so it sorts low (it is not a concern).
  aboveAdequateNoUl,

  /// 100–200% of the intake target for a UL-bounded nutrient.
  abundant,

  /// >200% of the intake target but still <80% of UL.
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
    this.maximumPctOfRda,
    this.pctOfUl,
    this.warning,
    this.rdaIsBaseline = false,
    this.ulIsFallback = false,
    this.ulAssessmentIndeterminate = false,
  });

  final NutrientTotal total;
  final NutrientTier tier;
  final double? rda;
  final double? ul;
  final double? pctOfRda;

  /// Target coverage at the maximum label-directed daily exposure. The
  /// primary [pctOfRda] remains based on the minimum/recommended exposure.
  final double? maximumPctOfRda;
  final double? pctOfUl;
  final String? warning;

  /// True when [rda] came from the anonymous adult fallback (Female
  /// 19-30) instead of a profile match. UI should indicate the value
  /// is a generic baseline so users know to complete their profile
  /// for personalized numbers.
  final bool rdaIsBaseline;

  /// True when [ul] came from the reference entry's anonymous `highest_ul`
  /// fallback instead of an exact demographic match. This is intentionally
  /// least restrictive, not conservative; UI copy should ask users to add a
  /// profile for personalized upper-limit checks.
  final bool ulIsFallback;

  /// A UL exists, but this label's form/source detail is insufficient for an
  /// honest comparison (for example, mixed-form Vitamin A without a known
  /// preformed fraction).
  final bool ulAssessmentIndeterminate;

  /// True when this nutrient should surface a visible warning to the
  /// user. The caller decides whether to render it as a chip, a
  /// banner, or an inline message.
  bool get shouldWarn =>
      tier == NutrientTier.approachingUl || tier == NutrientTier.exceedsUl;
}
