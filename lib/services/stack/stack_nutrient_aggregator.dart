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

import 'package:pharmaguide/core/units/dose_units.dart';
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
      // Pass 1 — parse every usable row for THIS product so we can apply
      // per-product rules (elemental vs compound dedup) before summing.
      final parsedRows = <_ParsedRow>[];
      for (final row in item.ingredients) {
        if (!_isUsableNutrientRow(row)) continue;

        final canonical = _readCanonicalId(row);
        if (canonical == null || canonical.isEmpty) continue;

        final amount = _readAmount(row);
        if (amount == null || amount <= 0) continue;

        parsedRows.add(
          _ParsedRow(
            row: row,
            canonicalId: canonical,
            amount: amount,
            unit: _readUnit(row),
            displayName: _readDisplayName(row) ?? canonical,
          ),
        );
      }

      // ELEMENTAL vs COMPOUND DEDUP (within one product only).
      //
      // Verified pipeline bug (dsld_id 315678, 'Magnesium Glycinate
      // 400 mg'): the blob carries TWO rows with canonical 'magnesium' —
      // {'Magnesium', 60 mg} (elemental, the label-declared total) and
      // {'Magnesium Glycinate', 400 mg} (compound weight; glycinate is
      // ~14% elemental Mg). Summing both yields 460 mg and a false
      // exceeds-UL warning. When a product lists a bare elemental row
      // for a nutrient, that row IS the total — compound-named siblings
      // are excluded from the sum (but kept visible as excluded
      // contributions). Products listing only form rows ('Magnesium
      // (as oxide)' + 'Magnesium (as citrate)') have no bare elemental
      // row conflict and legitimately sum. Cross-product summing is
      // never affected.
      final compoundDuplicates = _compoundDuplicateRows(parsedRows);

      for (final parsed in parsedRows) {
        final row = parsed.row;
        final canonical = parsed.canonicalId;
        final amount = parsed.amount;
        final unit = parsed.unit;
        final displayName = parsed.displayName;
        final exclusionReason = compoundDuplicates.contains(parsed)
            ? NutrientExclusionReason.compoundFormDuplicate
            : _exclusionReason(row, unit);

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
          ingredientName: displayName,
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
          // Compound-form duplicates are a dedup decision, not a unit
          // problem — don't raise the unit-conflict flag for them.
          if (exclusionReason !=
              NutrientExclusionReason.compoundFormDuplicate) {
            total.hasUnitConflict = true;
          }
          continue;
        }

        if (total.unit.isEmpty) total.unit = unit;

        // Only sum into the running total if the unit matches the
        // canonical unit established by the first contribution.
        // Mismatched units flag the total but do not corrupt the sum.
        final convertedAmount = amountInMass(
          amount,
          from: unit,
          to: total.unit,
        );
        if (convertedAmount != null) {
          total.contributions.add(
            NutrientContribution(
              stackEntryId: item.stackEntryId,
              productName: item.productName,
              ingredientName: displayName,
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

  /// Extract the pipeline's own per-nutrient UL verdicts from the raw rows,
  /// keyed by canonical id (matching [aggregate]'s keys).
  ///
  /// When the pipeline has already decided a row's UL status (emitting
  /// `over_ul` / `pct_ul`) the client should PREFER that verdict over its
  /// own recompute: the pipeline resolves elemental-vs-compound mass and
  /// form-aware unit conversions that cannot be reconstructed from raw blob
  /// quantities. [StackUlChecker.check] consumes this map.
  ///
  /// Rows the pipeline declined to gate (`ul_gate_eligible == false`) or
  /// skipped (`skip_ul_check == true`) contribute NO verdict — an incidental
  /// `over_ul`/`pct_ul` on such a row would be misleading. When several rows
  /// map to one canonical id, the most severe verdict wins.
  Map<String, PipelineUlVerdict> extractPipelineUlVerdicts(
    List<StackItemNutrients> stack,
  ) {
    final byCanonical = <String, PipelineUlVerdict>{};
    for (final item in stack) {
      for (final row in item.ingredients) {
        if (!_isUsableNutrientRow(row)) continue;
        if (row['skip_ul_check'] == true) continue;
        if (row['ul_gate_eligible'] == false) continue;

        final overUl = _readOverUl(row);
        final pctUl = _asDouble(row['pct_ul']);
        if (overUl == null && pctUl == null) continue;

        final canonical = _readCanonicalId(row);
        if (canonical == null || canonical.isEmpty) continue;

        final verdict = PipelineUlVerdict(overUl: overUl, pctUl: pctUl);
        final existing = byCanonical[canonical];
        byCanonical[canonical] = existing == null
            ? verdict
            : _mostSevereVerdict(existing, verdict);
      }
    }
    return byCanonical;
  }

  static bool? _readOverUl(Map<String, dynamic> row) {
    final v = row['over_ul'];
    return v is bool ? v : null;
  }

  /// Merge two verdicts for the same canonical nutrient, keeping the most
  /// severe signal: any `over_ul == true` wins; otherwise the larger
  /// `pct_ul`; a definite `over_ul == false` is preserved over an absent one.
  static PipelineUlVerdict _mostSevereVerdict(
    PipelineUlVerdict a,
    PipelineUlVerdict b,
  ) {
    final bool? overUl;
    if (a.overUl == true || b.overUl == true) {
      overUl = true;
    } else if (a.overUl == false || b.overUl == false) {
      overUl = false;
    } else {
      overUl = null;
    }
    final pctA = a.pctUl;
    final pctB = b.pctUl;
    final double? pctUl;
    if (pctA == null) {
      pctUl = pctB;
    } else if (pctB == null) {
      pctUl = pctA;
    } else {
      pctUl = pctA >= pctB ? pctA : pctB;
    }
    return PipelineUlVerdict(overUl: overUl, pctUl: pctUl);
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
      // Display roll-up of `form_of` children to their parent (e.g.
      // vitamin_k1 → vitamin_k), pipeline-computed from the IQM
      // match_rules.target_id. Lets Vitamin K1 + K2 aggregate as one
      // "Vitamin K". Null on most rows and on catalogs built before this
      // field existed, so it falls through to canonical_id (dual-read safe).
      row['nutrient_group_id'],
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
    // The pipeline declined to UL-gate this row because its disclosed
    // quantity is a COMPOUND mass, not elemental-comparable to the
    // reference UL (`ul_gate_ineligible_reason == "compound_mass_not_elemental"`).
    // Honor that decision and keep the compound mass out of the recompute:
    // a single-form compound product (e.g. Magnesium L-Threonate 2000 mg
    // with no bare-elemental sibling) must not be measured against the
    // elemental UL. Reuse `compoundFormDuplicate` — same "compound weight is
    // not elemental, don't sum it" semantics — so this does NOT raise the
    // unit-conflict flag. Opt-out only (`== false`): absent/true are summed,
    // so catalogs built before the field existed are unaffected.
    if (row['ul_gate_eligible'] == false) {
      return NutrientExclusionReason.compoundFormDuplicate;
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

  /// Identify rows that are compound-form duplicates of a bare elemental
  /// row for the same canonical nutrient WITHIN one product.
  ///
  /// A row is "elemental" when its display name equals the canonical
  /// nutrient name (case / whitespace / underscore insensitive), either
  /// directly ('Magnesium') or after stripping parentheticals
  /// ('Magnesium (elemental)', 'Magnesium (as oxide)'). When a canonical
  /// group contains BOTH elemental and non-elemental (compound-named)
  /// rows, the compound rows are duplicates: the elemental row is the
  /// label-declared total. Groups that are all-elemental (multi-form
  /// labels) or all-compound are left untouched and sum normally.
  static Set<_ParsedRow> _compoundDuplicateRows(List<_ParsedRow> rows) {
    if (rows.length < 2) return const {};

    final byCanonical = <String, List<_ParsedRow>>{};
    for (final row in rows) {
      byCanonical.putIfAbsent(row.canonicalId, () => []).add(row);
    }

    final duplicates = <_ParsedRow>{};
    for (final group in byCanonical.values) {
      if (group.length < 2) continue;
      final hasElemental = group.any(
        (r) => _isElementalName(r.displayName, r.canonicalId),
      );
      if (!hasElemental) continue;
      for (final row in group) {
        if (!_isElementalName(row.displayName, row.canonicalId)) {
          duplicates.add(row);
        }
      }
    }
    return duplicates;
  }

  /// True when [displayName] is the bare elemental nutrient name for
  /// [canonicalId]: equal after normalization, or equal after stripping
  /// a parenthetical (e.g. 'Magnesium (elemental)' → 'Magnesium').
  /// Deliberately conservative — anything that doesn't match exactly is
  /// treated as a distinct (compound) form.
  static bool _isElementalName(String displayName, String canonicalId) {
    final canonical = _normalizeNameKey(canonicalId);
    if (canonical.isEmpty) return false;
    if (_normalizeNameKey(displayName) == canonical) return true;
    final stripped = displayName.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    return _normalizeNameKey(stripped) == canonical;
  }

  /// Lowercase, trim, and collapse whitespace/underscore runs to single
  /// spaces so 'vitamin_d3' and 'Vitamin D3' compare equal.
  static String _normalizeNameKey(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), ' ');
  }
}

/// The pipeline's authored UL verdict for one canonical nutrient, extracted
/// from raw `rda_ul_data`-style rows by
/// [StackNutrientAggregator.extractPipelineUlVerdicts].
///
/// The client prefers this over recomputing percent-of-UL from raw blob
/// quantities: the pipeline sees elemental-vs-compound mass and form-aware
/// unit conversions the client cannot re-derive. When the verdict is absent
/// or non-definitive, the client falls back to its own recompute.
class PipelineUlVerdict {
  const PipelineUlVerdict({this.overUl, this.pctUl});

  /// Pipeline's boolean UL gate. `true` = over the limit, `false` = within,
  /// `null` = the pipeline did not emit a boolean decision for this row.
  final bool? overUl;

  /// Pipeline's percent-of-UL for the row, when emitted.
  final double? pctUl;

  /// Whether the pipeline emitted any actionable UL signal at all. A verdict
  /// that is not definitive is ignored and the client recomputes.
  bool get isDefinitive => overUl != null || pctUl != null;

  /// Whether the pipeline judged this nutrient OVER its UL. `over_ul` is the
  /// authoritative gate; `pct_ul >= 150` mirrors the pipeline's B7
  /// (150%-of-UL) exceedance threshold as a fallback when only the percentage
  /// was emitted. An explicit `over_ul == false` always wins.
  bool get exceedsUl {
    if (overUl == true) return true;
    if (overUl == false) return false;
    return (pctUl ?? 0) >= 150.0;
  }
}

/// One parsed-and-usable ingredient row, scoped to a single product.
/// Identity semantics (default ==) are intentional: the dedup pass marks
/// specific row instances, not value-equal rows.
class _ParsedRow {
  _ParsedRow({
    required this.row,
    required this.canonicalId,
    required this.amount,
    required this.unit,
    required this.displayName,
  });

  final Map<String, dynamic> row;
  final String canonicalId;
  final double amount;
  final String unit;
  final String displayName;
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
