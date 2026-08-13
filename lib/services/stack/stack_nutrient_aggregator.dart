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
// * Rows whose disclosed quantity is explicitly marked as compound mass
//   rather than an elemental nutrient amount
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
import 'package:pharmaguide/core/utils/num_parse.dart';
import 'package:pharmaguide/services/health/dose_safety.dart';
import 'package:pharmaguide/services/ingredients/elemental_form_dedupe.dart';
import 'package:pharmaguide/services/ingredients/ingredient_row_fields.dart';
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
        final isUlScopedComponent = row['dose_role'] == 'ul_scoped_component';
        if (!isUlScopedComponent && !isUsableDoseRow(row)) continue;

        final canonical = readCanonicalId(row);
        if (canonical == null || canonical.isEmpty) continue;

        final amount = readDoseAmount(row);
        if (amount == null || amount <= 0) continue;
        final adequacyAmount = readAdequacyDoseAmount(row) ?? amount;
        if (adequacyAmount <= 0) continue;

        parsedRows.add(
          _ParsedRow(
            row: row,
            canonicalId: canonical,
            amount: amount,
            adequacyAmount: adequacyAmount,
            unit: readDoseUnit(row),
            displayName: readNutrientDisplayName(row) ?? canonical,
            ingredientName: readDisplayName(row) ?? canonical,
            hasAuthoredGroupName:
                row['nutrient_group_name']?.toString().trim().isNotEmpty ==
                true,
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
      final legacyDeclaredTotalDuplicates = _legacyDeclaredTotalDuplicateRows(
        parsedRows,
      );

      for (final parsed in parsedRows) {
        final row = parsed.row;
        final canonical = parsed.canonicalId;
        final amount = parsed.amount;
        final unit = parsed.unit;
        final displayName = parsed.displayName;
        final ingredientName = parsed.ingredientName;
        final isUlScopedComponent = row['dose_role'] == 'ul_scoped_component';
        final exclusionReason = compoundDuplicates.contains(parsed)
            ? NutrientExclusionReason.compoundFormDuplicate
            : legacyDeclaredTotalDuplicates.contains(parsed)
            ? NutrientExclusionReason.declaredTotalDuplicate
            : _exclusionReason(row, unit);

        final total = accum.putIfAbsent(
          canonical,
          () => _MutableTotal(
            canonicalId: canonical,
            displayName: displayName,
            unit: exclusionReason == null ? unit : '',
            hasAuthoredDisplayName: parsed.hasAuthoredGroupName,
          ),
        );

        final rawContribution = NutrientContribution(
          stackEntryId: item.stackEntryId,
          productName: item.productName,
          ingredientName: ingredientName,
          amount: amount,
          minimumAmount: parsed.adequacyAmount,
          unit: unit,
        );

        // Intake and UL exposure are deliberately separate. The label total
        // always owns the amount shown to the user; a form-specific child can
        // own only the UL comparison without becoming a second intake dose.
        if (_hasUlExposureContract(row)) {
          total.hasUlExposureContract = true;
        }
        final canContributeToUl =
            isUlScopedComponent || exclusionReason == null;
        if (canContributeToUl && isUlEvaluationEligible(row)) {
          total.addUlComparableAmount(amount, unit);
        } else if (canContributeToUl && _isUnresolvedUlContribution(row)) {
          total.hasUnresolvedUlContribution = true;
        }

        if (isUlScopedComponent) {
          // This child is still represented in the label hierarchy. It is not
          // an excluded or missing amount; it simply has a different job in
          // the stack calculation.
          continue;
        }

        if (exclusionReason != null) {
          total.excludedContributions.add(
            ExcludedNutrientContribution(
              contribution: rawContribution,
              reason: exclusionReason,
            ),
          );
          // Missing or unsupported label metadata is traceable, but it is not
          // evidence that two disclosed quantities use incompatible units.
          // The conflict flag is reserved for an actual failed conversion.
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
        final convertedAdequacyAmount = amountInMass(
          parsed.adequacyAmount,
          from: unit,
          to: total.unit,
        );
        if (convertedAmount != null && convertedAdequacyAmount != null) {
          total.contributions.add(
            NutrientContribution(
              stackEntryId: item.stackEntryId,
              productName: item.productName,
              ingredientName: ingredientName,
              amount: convertedAmount,
              minimumAmount: convertedAdequacyAmount,
              unit: total.unit,
            ),
          );
          total.totalAmount += convertedAmount;
          total.minimumTotalAmount += convertedAdequacyAmount;
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
        if (parsed.hasAuthoredGroupName) {
          total.displayName = displayName;
          total.hasAuthoredDisplayName = true;
        } else if (!total.hasAuthoredDisplayName &&
            displayName.length > total.displayName.length) {
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
          minimumTotalAmount: value.minimumTotalAmount,
          unit: value.unit,
          contributions: List.unmodifiable(value.contributions),
          hasUnitConflict: value.hasUnitConflict,
          excludedContributions: List.unmodifiable(value.excludedContributions),
          ulComparableTotalAmount: value.ulComparableTotalAmount,
          ulComparableUnit: value.ulComparableUnit,
          hasUlExposureContract: value.hasUlExposureContract,
          hasUnresolvedUlContribution:
              value.hasUnresolvedUlContribution && !value.hasCompleteUlCoverage,
        ),
      ),
    );
  }

  static bool _hasUlExposureContract(Map<String, dynamic> row) =>
      row.containsKey('skip_ul_check') ||
      row.containsKey('ul_gate_eligible') ||
      row.containsKey('ul_assessment_status') ||
      row.containsKey('dose_role');

  static bool _isUnresolvedUlContribution(Map<String, dynamic> row) {
    if (isUlEvaluationEligible(row)) return false;
    final status = row['ul_assessment_status']?.toString().trim().toLowerCase();
    if (status == 'indeterminate') return true;
    if (status == 'not_applicable') return false;

    final reason = (row['skip_ul_reason'] ?? row['ul_gate_ineligible_reason'])
        ?.toString()
        .trim()
        .toLowerCase();
    return !const {
      'compound_duplicate_row',
      'compound_mass_not_elemental',
      'form_component_of_declared_total',
      'non_folic_acid_folate_ul_basis',
      'outside_ul_scope',
    }.contains(reason);
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
        if (!isUsableDoseRow(row)) continue;
        if (!isUlEvaluationEligible(row)) continue;

        final overUl = _readOverUl(row);
        final pctUl = asFiniteDouble(row['pct_ul']);
        if (overUl == null && pctUl == null) continue;

        final canonical = readCanonicalId(row);
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
  NutrientExclusionReason? _exclusionReason(
    Map<String, dynamic> row,
    String unit,
  ) {
    // UL eligibility and intake visibility are different questions.
    // `skip_ul_check` means the pipeline could not make a safe-limit verdict;
    // it does not erase a known label amount from the user's intake display.
    //
    // The one authored exception is compound mass: a value such as 2,000 mg
    // magnesium L-threonate is not 2,000 mg elemental magnesium and must not
    // be added to an elemental total. Keep that row traceable as an excluded
    // contribution without presenting it as a unit conflict.
    if (row['ul_gate_eligible'] == false &&
        row['ul_gate_ineligible_reason'] == 'compound_mass_not_elemental') {
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
        (r) => isElementalIngredientName(r.ingredientName, r.canonicalId),
      );
      if (!hasElemental) continue;
      for (final row in group) {
        if (!isElementalIngredientName(row.ingredientName, row.canonicalId)) {
          duplicates.add(row);
        }
      }
    }
    return duplicates;
  }

  /// Temporarily recognize pre-lineage blobs that duplicate a declared folate
  /// DFE total as an L-5-MTHF re-derivation. This is intentionally narrow:
  /// both rows must be in one product and canonical group, the retained row
  /// must be a literal DFE label total, and the excluded row must be an
  /// L-5-MTHF/methylfolate mass row converted to a near-identical DFE amount.
  ///
  /// Pipeline lineage fields supersede this compatibility guard once cached
  /// detail blobs rotate.
  static Set<_ParsedRow> _legacyDeclaredTotalDuplicateRows(
    List<_ParsedRow> rows,
  ) {
    final byCanonical = <String, List<_ParsedRow>>{};
    for (final row in rows) {
      if (!row.canonicalId.contains('folate')) continue;
      byCanonical.putIfAbsent(row.canonicalId, () => []).add(row);
    }

    final duplicates = <_ParsedRow>{};
    for (final group in byCanonical.values) {
      if (group.length < 2) continue;
      final declaredTotals = group.where(_isLegacyDeclaredFolateTotal);
      for (final declaredTotal in declaredTotals) {
        for (final candidate in group) {
          if (identical(candidate, declaredTotal)) continue;
          if (_isMatchingLegacyFolateForm(
            declaredTotal: declaredTotal,
            candidate: candidate,
          )) {
            duplicates.add(candidate);
          }
        }
      }
    }
    return duplicates;
  }

  static bool _isLegacyDeclaredFolateTotal(_ParsedRow row) {
    final ingredient = (row.row['ingredient'] ?? row.ingredientName)
        .toString()
        .trim()
        .toLowerCase();
    final rawUnit = row.row['unit']?.toString().trim().toLowerCase() ?? '';
    return ingredient == 'folate' && rawUnit.contains('dfe');
  }

  static bool _isMatchingLegacyFolateForm({
    required _ParsedRow declaredTotal,
    required _ParsedRow candidate,
  }) {
    final ingredient = (candidate.row['ingredient'] ?? candidate.ingredientName)
        .toString()
        .toLowerCase();
    if (!ingredient.contains('mthf') && !ingredient.contains('methylfolate')) {
      return false;
    }

    final rawUnit =
        candidate.row['unit']?.toString().trim().toLowerCase() ?? '';
    final convertedUnit =
        candidate.row['converted_unit']?.toString().trim().toLowerCase() ?? '';
    if (rawUnit.contains('dfe') || !convertedUnit.contains('dfe')) return false;

    final original = asFiniteDouble(candidate.row['quantity']);
    final converted = asFiniteDouble(candidate.row['converted_quantity']);
    if (original == null ||
        original <= 0 ||
        converted == null ||
        converted <= 0) {
      return false;
    }

    final conversion = candidate.row['conversion_evidence'];
    final factor = conversion is Map
        ? asFiniteDouble(conversion['conversion_factor'])
        : null;
    if (factor == null || factor <= 1) return false;

    final tolerance = declaredTotal.amount * 0.025;
    return (converted - declaredTotal.amount).abs() <= tolerance;
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
    required this.adequacyAmount,
    required this.unit,
    required this.displayName,
    required this.ingredientName,
    required this.hasAuthoredGroupName,
  });

  final Map<String, dynamic> row;
  final String canonicalId;
  final double amount;
  final double adequacyAmount;
  final String unit;
  final String displayName;
  final String ingredientName;
  final bool hasAuthoredGroupName;
}

/// Internal mutable carrier used during accumulation. We convert to
/// the immutable [NutrientTotal] at the end of [aggregate].
class _MutableTotal {
  _MutableTotal({
    required this.canonicalId,
    required this.displayName,
    required this.unit,
    required this.hasAuthoredDisplayName,
  });

  final String canonicalId;
  String displayName;
  String unit;
  bool hasAuthoredDisplayName;
  double totalAmount = 0.0;
  double minimumTotalAmount = 0.0;
  double? ulComparableTotalAmount;
  String? ulComparableUnit;
  bool hasUlExposureContract = false;
  bool hasUnresolvedUlContribution = false;
  bool hasUnitConflict = false;
  final List<NutrientContribution> contributions = [];
  final List<ExcludedNutrientContribution> excludedContributions = [];

  void addUlComparableAmount(double amount, String unit) {
    if (unit.isEmpty) {
      hasUnresolvedUlContribution = true;
      return;
    }
    final targetUnit = ulComparableUnit;
    if (targetUnit == null || targetUnit.isEmpty) {
      ulComparableUnit = unit;
      ulComparableTotalAmount = amount;
      return;
    }
    final converted = amountInMass(amount, from: unit, to: targetUnit);
    if (converted == null) {
      hasUnresolvedUlContribution = true;
      return;
    }
    ulComparableTotalAmount = (ulComparableTotalAmount ?? 0) + converted;
  }

  bool get hasCompleteUlCoverage {
    final amount = ulComparableTotalAmount;
    final ulUnit = ulComparableUnit;
    if (amount == null || ulUnit == null || unit.isEmpty) return false;
    final converted = amountInMass(amount, from: ulUnit, to: unit);
    if (converted == null) return false;
    final tolerance = totalAmount.abs() * 0.025 + 0.001;
    return (converted - totalAmount).abs() <= tolerance;
  }
}
