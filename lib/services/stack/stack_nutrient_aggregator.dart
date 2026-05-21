// StackNutrientAggregator — pure-function nutrient summer for the
// user's stack. Takes per-product ingredient lists and produces a
// map keyed by canonical_id with running totals.
//
// DESIGN CONTRACT
//
// This class is intentionally sync and state-free. The async detail-
// blob fetch happens upstream in a Riverpod FutureProvider. That
// separation lets us test the math under dozens of edge-case stacks
// without touching a database or network.
//
// INPUT DEFENSIVENESS
//
// Pipeline schema drift is the biggest risk. `detail_blob.ingredients`
// has shipped with different field names over time:
//   * `mapped_name`, `standard_name`, `canonical_id`  — any may exist
//   * `per_day_max`, `converted_quantity`, `amount`    — any may exist
//   * `converted_unit`, `normalizedUnit`, `unit`        — any may exist
// We read every plausible field in priority order. If nothing usable
// is found, the row is skipped — never crash the app.
//
// WHAT WE SKIP
//
// * Rows without a usable canonical id
// * Rows without a numeric amount
// * Rows marked `is_active: false` (pipeline inactive flag)
// * Rows marked `is_label_descriptor: true` (non-dose label fragments)
// * Rows marked `is_proprietary_blend: true` (blend containers are
//   not nutrients, their children carry the real doses)
// * Rows marked `is_parent_total: true` (nested-form summaries that
//   would double-count children)
// * Rows with missing / "NP" / unsupported units
// * Rows where the pipeline explicitly skipped UL checking
//
// UNIT CONFLICTS
//
// When two products report the same nutrient in incompatible units
// (mg vs mcg, IU vs mg, etc.), we do NOT convert. The first unit
// seen for a given canonical id becomes canonical. Subsequent
// contributions in different units are still recorded in the excluded
// contribution list but excluded from the sum, and the total is flagged
// with `hasUnitConflict: true` so the UI can surface it.
// Silent conversion is how medical-grade bugs ship.

import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

class StackNutrientAggregator {
  const StackNutrientAggregator();

  /// Sum every active ingredient across a stack.
  ///
  /// Keys of the returned map are canonical ids (lowercased, trimmed).
  /// Values are [NutrientTotal]s with full contribution lists.
  ///
  /// Empty input returns an empty map. Unknown shape in individual
  /// ingredient rows is logged silently and skipped — the result is
  /// still usable even if one product has dirty data.
  Map<String, NutrientTotal> aggregate(List<StackItemNutrients> stack) {
    // Intermediate mutable accumulator keyed by canonical id.
    final accum = <String, _MutableTotal>{};

    for (final item in stack) {
      for (final row in item.ingredients) {
        if (!_isUsableNutrientRow(row)) continue;

        final canonical = _readCanonicalId(row);
        if (canonical == null || canonical.isEmpty) continue;

        final amount = _readAmount(row);
        if (amount == null || amount <= 0) continue;

        final unit = _readUnit(row);
        final displayName = _readDisplayName(row) ?? canonical;
        final exclusionReason = _exclusionReason(row, unit);

        final total = accum.putIfAbsent(
          canonical,
          () => _MutableTotal(
            canonicalId: canonical,
            displayName: displayName,
            unit: exclusionReason == null ? unit : '',
          ),
        );

        final rawContribution = NutrientContribution(
          stackEntryId: item.stackEntryId,
          productName: item.productName,
          amount: amount,
          unit: unit,
        );

        if (exclusionReason != null) {
          total.excludedContributions.add(
            ExcludedNutrientContribution(
              contribution: rawContribution,
              reason: exclusionReason,
            ),
          );
          total.hasUnitConflict = true;
          continue;
        }

        if (total.unit.isEmpty) total.unit = unit;

        // Only sum into the running total if the unit matches the
        // canonical unit established by the first contribution.
        // Mismatched units flag the total but do not corrupt the sum.
        final convertedAmount = _amountInUnit(
          amount,
          from: unit,
          to: total.unit,
        );
        if (convertedAmount != null) {
          total.contributions.add(
            NutrientContribution(
              stackEntryId: item.stackEntryId,
              productName: item.productName,
              amount: convertedAmount,
              unit: total.unit,
            ),
          );
          total.totalAmount += convertedAmount;
        } else {
          total.hasUnitConflict = true;
          total.excludedContributions.add(
            ExcludedNutrientContribution(
              contribution: rawContribution,
              reason: NutrientExclusionReason.unitConflict,
            ),
          );
        }

        // Prefer the longest display name we see — pipeline rows
        // sometimes have terse shorthand in one product and the full
        // name in another.
        if (displayName.length > total.displayName.length) {
          total.displayName = displayName;
        }
      }
    }

    return accum.map(
      (key, value) => MapEntry(
        key,
        NutrientTotal(
          canonicalId: value.canonicalId,
          displayName: value.displayName,
          totalAmount: value.totalAmount,
          unit: value.unit,
          contributions: List.unmodifiable(value.contributions),
          hasUnitConflict: value.hasUnitConflict,
          excludedContributions: List.unmodifiable(value.excludedContributions),
        ),
      ),
    );
  }

  /// Return false for rows that should never count toward any total:
  /// inactive ingredients, proprietary blend containers (children
  /// carry the real dose), and parent-total rows in nested nutrient
  /// trees.
  bool _isUsableNutrientRow(Map<String, dynamic> row) {
    final isActive = row['is_active'];
    if (isActive is bool && !isActive) return false;

    final isLabelDescriptor = row['is_label_descriptor'];
    if (isLabelDescriptor is bool && isLabelDescriptor) return false;

    final isBlend = row['is_proprietary_blend'];
    if (isBlend is bool && isBlend) return false;

    final isParentTotal = row['is_parent_total'];
    if (isParentTotal is bool && isParentTotal) return false;

    return true;
  }

  /// Read the canonical id in priority order, normalising to a
  /// lowercase trimmed string. `mapped_name` is the field the current
  /// pipeline writes; `canonical_id` and `standard_name` are fallbacks
  /// for older or differently-shaped blobs.
  String? _readCanonicalId(Map<String, dynamic> row) {
    final candidates = <dynamic>[
      row['canonical_id'],
      row['mapped_name'],
      row['standard_name'],
      row['standardName'],
      row['normalized_key'],
    ];
    for (final c in candidates) {
      if (c is String && c.trim().isNotEmpty) {
        return c.trim().toLowerCase();
      }
    }
    return null;
  }

  /// Human-readable name for the UI. Falls back to the canonical id
  /// if nothing better is present.
  String? _readDisplayName(Map<String, dynamic> row) {
    final candidates = <dynamic>[
      row['display_name'],
      row['name'],
      row['standard_name'],
      row['standardName'],
    ];
    for (final c in candidates) {
      if (c is String && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }

  /// Read a numeric amount tolerating int, double, or numeric strings.
  /// The pipeline has historically used any of: `per_day_max`,
  /// `converted_quantity`, `normalized_amount`, `normalizedAmount`,
  /// `quantity`, `amount`, `dosage`.
  double? _readAmount(Map<String, dynamic> row) {
    final candidates = <dynamic>[
      row['per_day_max'],
      row['daily_amount'],
      row['converted_quantity'],
      row['normalized_amount'],
      row['normalizedAmount'],
      row['quantity'],
      row['amount'],
      row['dosage'],
    ];
    for (final c in candidates) {
      final parsed = _asDouble(c);
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Read the unit string tolerating both snake_case and camelCase.
  String _readUnit(Map<String, dynamic> row) {
    final candidates = <dynamic>[
      row['daily_amount_unit'],
      row['converted_unit'],
      row['normalized_unit'],
      row['normalizedUnit'],
      row['unit'],
      row['dosage_unit'],
    ];
    for (final c in candidates) {
      if (c is String && c.trim().isNotEmpty) {
        return c.trim().toLowerCase();
      }
    }
    return '';
  }

  NutrientExclusionReason? _exclusionReason(
    Map<String, dynamic> row,
    String unit,
  ) {
    if (row['skip_ul_check'] == true) {
      return NutrientExclusionReason.skippedByPipeline;
    }
    if (unit.isEmpty) return NutrientExclusionReason.missingUnit;
    final normalized = unit.toLowerCase().trim();
    if (normalized == 'np' ||
        normalized == 'n/p' ||
        normalized == 'not provided') {
      return NutrientExclusionReason.notProvidedUnit;
    }
    if (normalized == 'unspecified' || normalized == 'unknown') {
      return NutrientExclusionReason.unsupportedUnit;
    }
    return null;
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v.isFinite ? v : null;
    if (v is int) return v.toDouble();
    if (v is String) {
      final parsed = double.tryParse(v.trim());
      return (parsed != null && parsed.isFinite) ? parsed : null;
    }
    return null;
  }

  /// Convert [amount] into [to] when the units are exactly equal or are
  /// simple metric mass units. We intentionally do not convert IU, RAE, DFE,
  /// NE, or alpha-tocopherol units here because those depend on nutrient form
  /// and must arrive pre-converted from the pipeline.
  static double? _amountInUnit(
    double amount, {
    required String from,
    required String to,
  }) {
    final fromUnit = _normalizeUnit(from);
    final toUnit = _normalizeUnit(to);
    if (fromUnit.isEmpty || toUnit.isEmpty) return null;
    if (fromUnit == toUnit) return amount;

    final fromGrams = _simpleMassGramsFactor(fromUnit);
    final toGrams = _simpleMassGramsFactor(toUnit);
    if (fromGrams == null || toGrams == null) return null;
    return amount * fromGrams / toGrams;
  }

  static double? _simpleMassGramsFactor(String unit) {
    return switch (unit) {
      'g' => 1.0,
      'gram' => 1.0,
      'grams' => 1.0,
      'gram(s)' => 1.0,
      'mg' => 0.001,
      'mcg' => 0.000001,
      'microgram' => 0.000001,
      'micrograms' => 0.000001,
      _ => null,
    };
  }

  static String _normalizeUnit(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll('µg', 'mcg')
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}

/// Internal mutable carrier used during accumulation. We convert to
/// the immutable [NutrientTotal] at the end of [aggregate].
class _MutableTotal {
  _MutableTotal({
    required this.canonicalId,
    required this.displayName,
    required this.unit,
  });

  final String canonicalId;
  String displayName;
  String unit;
  double totalAmount = 0.0;
  bool hasUnitConflict = false;
  final List<NutrientContribution> contributions = [];
  final List<ExcludedNutrientContribution> excludedContributions = [];
}
