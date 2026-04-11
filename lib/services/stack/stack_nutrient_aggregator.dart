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
//   * `amount`, `normalizedAmount`, `quantity`         — any may exist
//   * `unit`, `normalizedUnit`                         — any may exist
// We read every plausible field in priority order. If nothing usable
// is found, the row is skipped — never crash the app.
//
// WHAT WE SKIP
//
// * Rows without a usable canonical id
// * Rows without a numeric amount
// * Rows marked `is_active: false` (pipeline inactive flag)
// * Rows marked `is_proprietary_blend: true` (blend containers are
//   not nutrients, their children carry the real doses)
// * Rows marked `is_parent_total: true` (nested-form summaries that
//   would double-count children)
//
// UNIT CONFLICTS
//
// When two products report the same nutrient in incompatible units
// (mg vs mcg, IU vs mg, etc.), we do NOT convert. The first unit
// seen for a given canonical id becomes canonical. Subsequent
// contributions in different units are still recorded in the
// contribution list but excluded from the sum, and the total is
// flagged with `hasUnitConflict: true` so the UI can surface it.
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

        final total = accum.putIfAbsent(
          canonical,
          () => _MutableTotal(
            canonicalId: canonical,
            displayName: displayName,
            unit: unit,
          ),
        );

        final contribution = NutrientContribution(
          stackEntryId: item.stackEntryId,
          productName: item.productName,
          amount: amount,
          unit: unit,
        );
        total.contributions.add(contribution);

        // Only sum into the running total if the unit matches the
        // canonical unit established by the first contribution.
        // Mismatched units flag the total but do not corrupt the sum.
        if (_unitsMatch(unit, total.unit)) {
          total.totalAmount += amount;
        } else {
          total.hasUnitConflict = true;
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
  /// The pipeline has historically used any of: `normalized_amount`,
  /// `normalizedAmount`, `quantity`, `amount`, `dosage`.
  double? _readAmount(Map<String, dynamic> row) {
    final candidates = <dynamic>[
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

  /// Case-insensitive unit equality. Also treats empty-string as a
  /// match with any unit — some legacy blobs omit the unit entirely,
  /// and we'd rather sum a row than drop it when the unit is simply
  /// missing. If this proves too loose we can tighten later.
  static bool _unitsMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return true;
    return a.toLowerCase() == b.toLowerCase();
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
  final String unit;
  double totalAmount = 0.0;
  bool hasUnitConflict = false;
  final List<NutrientContribution> contributions = [];
}
