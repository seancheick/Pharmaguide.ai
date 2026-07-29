// Shared readers for a raw pipeline ingredient / dose row.
//
// `detail_blob.ingredients` (and `rda_ul_data.analyzed_ingredients`) rows have
// shipped with drifting field names across the catalog's life: `quantity`,
// `converted_quantity`, `per_day_max`, `daily_amount`, `amount`, `dose_amount`
// have all meant "the dose", and `unit` / `converted_unit` / `daily_amount_unit`
// / `dose_unit` have all meant "the unit".
//
// Before this file, `stack_dose_summer`, `stack_nutrient_aggregator`, and
// `condition_gate` EACH carried their own private copy of "read the amount /
// unit / name / is-this-row-usable" logic — and the copies had DRIFTED:
//
//   * three different amount-field priorities. The summers read the per-day
//     fields (`per_day_max`, `converted_quantity`) BEFORE raw per-serving
//     `quantity`; `condition_gate` read `quantity` first and `per_day_max`
//     LAST — so on a "2 caps/day x 500 mg" row the condition gate saw 500
//     where the UL checker saw 1000.
//   * `condition_gate` omitted the proprietary-blend / parent-total usability
//     filter the summers enforced, so it double-counted nested-tree rows.
//   * only `stack_dose_summer` normalized the unit spelling; the aggregator
//     left `µg` unfolded.
//
// This is the single source of truth so the dose the UL checker sees, the dose
// the pairwise-threshold gate sees, and the dose the condition gate sees are
// the SAME number for the SAME row. Dose thresholds are all per-day, so the
// per-day-normalized fields deliberately win over the raw per-serving ones.

import 'package:pharmaguide/core/units/dose_units.dart';
import 'package:pharmaguide/core/utils/num_parse.dart';
import 'package:pharmaguide/services/ingredients/ingredient_canonicalizer.dart';

/// Numeric dose amount for [row], in priority order, or null when no field
/// carries a usable finite number.
///
/// Per-day-normalized fields (`per_day_max`, `daily_amount`,
/// `converted_quantity`) win over raw per-serving `quantity` / `amount`:
/// dose-safety thresholds are per-day, so a "2 servings/day x 500 mg" row must
/// read its per-day value, not the per-serving label number.
double? readDoseAmount(Map<String, dynamic> row) {
  const fields = <String>[
    'per_day_max',
    'daily_amount',
    'converted_quantity',
    'normalized_amount',
    'normalizedAmount',
    'quantity',
    'amount',
    'dose_amount',
    'dosage',
  ];
  for (final field in fields) {
    final parsed = asFiniteDouble(row[field]);
    if (parsed != null) return parsed;
  }
  return null;
}

/// Minimum/recommended daily exposure for adequacy comparisons.
///
/// RDA/AI coverage uses the dose a label recommends at the low end, while
/// safety/UL checks use [readDoseAmount]'s maximum daily exposure. When an
/// older blob has no `per_day_min`, fall back to the regular dose reader so
/// fixed-dose products retain their historical behavior.
double? readAdequacyDoseAmount(Map<String, dynamic> row) {
  final minimum = asFiniteDouble(row['per_day_min']);
  if (minimum != null) return minimum;

  final exposure = row['adequacy_exposure'];
  if (exposure is Map) {
    final amount = asFiniteDouble(exposure['per_day']);
    if (amount != null) return amount;
  }

  return readDoseAmount(row);
}

/// Dose unit for [row], normalized via [normalizeDoseUnit] (folds `µg`/`ug` →
/// `mcg`, `i.u.` → `iu`, …), or `''` when absent. Unit-field priority parallels
/// [readDoseAmount] — per-day-normalized unit fields win.
String readDoseUnit(Map<String, dynamic> row) {
  const fields = <String>[
    'daily_amount_unit',
    'converted_unit',
    'normalized_unit',
    'normalizedUnit',
    'unit',
    'dose_unit',
    'dosage_unit',
  ];
  for (final field in fields) {
    final raw = row[field];
    if (raw is String && raw.trim().isNotEmpty) {
      return normalizeDoseUnit(raw);
    }
  }
  return '';
}

/// Single canonical id for [row] (lowercased, trimmed), or null. Prefers the
/// pipeline's `nutrient_group_id` roll-up (so Vitamin K1 + K2 group as one
/// "Vitamin K") then the raw canonical / mapped fields.
String? readCanonicalId(Map<String, dynamic> row) {
  const fields = <String>[
    'nutrient_group_id',
    'canonical_id',
    'mapped_name',
    'standard_name',
    'standardName',
    'normalized_key',
  ];
  for (final field in fields) {
    final raw = row[field];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim().toLowerCase();
    }
  }
  return null;
}

/// Every canonical name-key [row] can match a threshold table under. A row
/// may carry several name fields (`standard_name`, `mapped_name`, …); each is
/// canonicalized (hyphen/punctuation-folded + aliased) into the returned set,
/// so a threshold keyed on any spelling still matches. Distinct from
/// [readCanonicalId], which picks ONE grouping id for summing.
Set<String> readDoseNameKeys(Map<String, dynamic> row) {
  final keys = <String>{};
  for (final field in const [
    'standard_name',
    'name',
    'ingredient',
    'mapped_name',
    'canonical_id',
    'normalized_key',
  ]) {
    final raw = row[field]?.toString();
    if (raw == null || raw.trim().isEmpty) continue;
    final key = canonicalizeIngredientName(raw);
    if (key.isNotEmpty) keys.add(key);
  }
  return keys;
}

/// Human-readable display name for [row], or null. `display_label` (the
/// pipeline's UI roll-up, e.g. "Magnesium (as Magnesium Glycinate)") wins.
String? readDisplayName(Map<String, dynamic> row) {
  const fields = <String>[
    'display_label',
    'display_name',
    'name',
    'standard_name',
    'standardName',
    'ingredient',
  ];
  for (final field in fields) {
    final raw = row[field]?.toString().trim();
    if (raw != null && raw.isNotEmpty) return raw;
  }
  return null;
}

/// Consumer display name for an aggregated nutrient total.
///
/// A producer-authored group name (for example, Vitamin K for K1 + K2) wins
/// only on the roll-up surface. [readDisplayName] remains the exact ingredient
/// label used by contributor and dose-threshold detail.
String? readNutrientDisplayName(Map<String, dynamic> row) {
  final groupName = row['nutrient_group_name']?.toString().trim();
  if (groupName != null && groupName.isNotEmpty) return groupName;
  return readDisplayName(row);
}

/// False for rows that must NEVER contribute to a dose sum:
///   * `is_active == false`            — pipeline inactive flag
///   * `is_label_descriptor == true`   — non-dose label fragment
///   * `is_proprietary_blend == true`  — blend CONTAINER (children carry doses)
///   * `is_parent_total == true`       — nested-tree roll-up (double-counts)
///   * `dose_role == form_component`   — context for a declared parent total
///
/// Opt-out semantics: a missing flag never excludes a row, so catalogs built
/// before a flag existed are unaffected.
bool isUsableDoseRow(Map<String, dynamic> row) {
  final isActive = row['is_active'];
  if (isActive is bool && !isActive) return false;

  final isLabelDescriptor = row['is_label_descriptor'];
  if (isLabelDescriptor is bool && isLabelDescriptor) return false;

  final isBlend = row['is_proprietary_blend'];
  if (isBlend is bool && isBlend) return false;

  final isParentTotal = row['is_parent_total'];
  if (isParentTotal is bool && isParentTotal) return false;

  if (row['dose_role'] == 'form_component') return false;

  return true;
}
