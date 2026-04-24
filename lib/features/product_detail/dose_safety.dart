/// Per-ingredient dose-vs-UL safety.
///
/// Routes through the pipeline's top-level `rda_ul_data.analyzed_ingredients`
/// block — the authoritative source for UL evaluation — matching by
/// `standard_name`. Respects `skip_ul_check`: when the pipeline
/// opts out of UL evaluation (e.g. `skip_ul_reason == "unknown_vitamin_form"`),
/// the UI must render a neutral state, not substitute its own judgment.
/// The clinical interpretation is owned by the pipeline — the UI
/// interprets, it does not reinterpret.
///
/// Implements the FLTR-11 safety hierarchy from the handoff §0:
///   UL exceeded  →  override all positive dose badges.
///   skip_ul_check →  render neutral; do not claim safe OR unsafe.
///
/// The fixtures in test/features/product_detail/dose_safety_test.dart
/// mirror the real blob shape under rda_ul_data.analyzed_ingredients.

library;

import 'package:pharmaguide/core/constants/severity.dart';

/// Per-ingredient dose safety state derived from the pipeline's UL
/// analysis block. Callers map each state to a visual badge.
enum DoseSafety {
  /// Pipeline explicitly skipped UL evaluation (unknown form, missing
  /// quantity, etc.). UI must render a neutral "dose not evaluated"
  /// state rather than a positive or negative judgment.
  skip,

  /// Disclosed dose exceeds the Tolerable Upper Intake Level. UI
  /// renders a High dose / danger badge and suppresses any positive
  /// bioavailability label.
  exceedsUl,

  /// No UL concern for this ingredient — either the ingredient has
  /// no matching UL entry in the blob, the UL field is absent, or
  /// the dose falls at or below the UL. Caller is free to apply its
  /// own dose-quality labeling (bioScore tiers).
  withinLimits,
}

/// Resolve the dose-safety state for a single ingredient against the
/// pipeline's `rda_ul_data.analyzed_ingredients` list. Pure function —
/// no widget/ref dependencies, so the logic is unit-testable in
/// isolation.
///
/// Matching is by `standard_name` (lowercase trim). Falls back to
/// `ingredient`/`name` fields on either side so blobs that emit a
/// slightly different field shape still match.
DoseSafety resolveDoseSafety({
  required Map<String, dynamic> ingredient,
  required List<Map<String, dynamic>>? ulAnalysis,
}) {
  final entry = matchUlEntry(ingredient, ulAnalysis);
  if (entry == null) return DoseSafety.withinLimits;
  if (entry['skip_ul_check'] == true) return DoseSafety.skip;

  // Per the FLTR-11 clarification: compare the actual disclosed
  // `quantity` against the UL, NOT `per_day_max`. per_day_max is a
  // pipeline-normalized scaling field (quantity × max servings/day)
  // used for stack aggregation. Using it would double-count the
  // serving math and fire false-positive UL alerts on any product
  // whose label allows multiple servings.
  final quantity = _asDouble(entry['quantity']) ??
      _asDouble(ingredient['quantity']);
  if (quantity == null || quantity <= 0) return DoseSafety.withinLimits;

  // UL resolution order honoring the pipeline contract:
  //   1. ul_for_default_profile — age/sex-aware UL when the pipeline
  //      resolved one for the anonymous default (adult 19-30).
  //   2. highest_ul — worst-case UL across demographics, used when
  //      the pipeline couldn't resolve a profile-specific UL.
  final ul = _asDouble(entry['ul_for_default_profile']) ??
      _asDouble(entry['highest_ul']);
  if (ul == null || ul <= 0) return DoseSafety.withinLimits;

  return quantity > ul ? DoseSafety.exceedsUl : DoseSafety.withinLimits;
}

/// Find the UL-analysis entry for an ingredient. Pulled out so the
/// per-ingredient tile can resolve once and pass the matched entry
/// down to the safety tag without re-scanning the list.
///
/// Returns null when no entry matches, when the list is null, or
/// when the ingredient has no `standard_name`/`name` to match on.
Map<String, dynamic>? matchUlEntry(
  Map<String, dynamic> ingredient,
  List<Map<String, dynamic>>? ulAnalysis,
) {
  if (ulAnalysis == null || ulAnalysis.isEmpty) return null;

  final target = _normalizedName(
    ingredient['standard_name'] ?? ingredient['name'],
  );
  if (target == null) return null;

  for (final entry in ulAnalysis) {
    final candidate = _normalizedName(
      entry['standard_name'] ?? entry['ingredient'],
    );
    if (candidate != null && candidate == target) return entry;
  }
  return null;
}

String? _normalizedName(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString().trim().toLowerCase();
  return s.isEmpty ? null : s;
}

/// A single per-ingredient UL exceedance surfaced by the pipeline's
/// `rda_ul_data.analyzed_ingredients[i].warnings[]` array. Each
/// pipeline-emitted warning string becomes one [UlExceedance] so the
/// UI can render one alert row per (ingredient, warning) pair.
class UlExceedance {
  final String standardName;
  final String warning;
  const UlExceedance({required this.standardName, required this.warning});
}

/// Extract UL-exceedance alerts from the pipeline's analysis block.
///
/// Respects the same [skip_ul_check] contract as [resolveDoseSafety]:
/// when the pipeline opts out of UL evaluation, no alert surfaces.
/// Entries with no warning strings, no standard_name, or a malformed
/// warnings field are skipped. Empty list when [ulAnalysis] is null
/// or carries no exceedances.
List<UlExceedance> extractUlExceedances(
  List<Map<String, dynamic>>? ulAnalysis,
) {
  if (ulAnalysis == null || ulAnalysis.isEmpty) return const [];
  final out = <UlExceedance>[];
  for (final entry in ulAnalysis) {
    if (entry['skip_ul_check'] == true) continue;
    final rawName = entry['standard_name'] ?? entry['ingredient'];
    final name = rawName?.toString().trim();
    if (name == null || name.isEmpty) continue;
    final warnings = entry['warnings'];
    if (warnings is! List) continue;
    for (final w in warnings) {
      final msg = w?.toString().trim() ?? '';
      if (msg.isEmpty) continue;
      out.add(UlExceedance(standardName: name, warning: msg));
    }
  }
  return out;
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v.isFinite ? v : null;
  if (v is int) return v.toDouble();
  if (v is String) {
    final parsed = double.tryParse(v.trim());
    return (parsed != null && parsed.isFinite) ? parsed : null;
  }
  return null;
}

// ----------------------------------------------------------------------
// FLTR-11a — Temporary Flutter dose guardrail
//
// Prevents caution+ warnings from firing on nutritional-range doses
// while waiting for pipeline E1.11 (dose-aware warning severity at
// source). Narrow scope: a small allowlist of ingredients where we
// know the pharmacologic/nutritional split crosses a clinical
// threshold. Everything outside the allowlist passes through
// unchanged — the UI never fabricates downgrade rules for
// ingredients it hasn't been told about.
//
// Delete this block when E1.11 ships. The pipeline is the right
// place to encode dose thresholds; this is insurance, not policy.
// ----------------------------------------------------------------------

/// Low-dose thresholds in the nutrient's own unit. A warning whose
/// severity is caution/avoid/contraindicated AND whose ingredient's
/// disclosed `quantity` (same unit) is strictly below the threshold
/// gets downgraded to [Severity.monitor] by
/// [applyLowDoseGuardrail]. Everything above the threshold —
/// supplemental + pharmacologic doses — passes through untouched.
///
/// Kept intentionally small. Add an entry only when there is a
/// concrete clinical threshold for the nutritional range (e.g.
/// niacin 35 mg = tolerable upper intake for supplemental
/// nicotinic acid; chromium 200 mcg = typical prenatal ceiling).
const _lowDoseThresholds = <String, ({double value, String unit})>{
  'niacin': (value: 35, unit: 'mg'),
  'vitamin b3 (niacin)': (value: 35, unit: 'mg'),
  'chromium': (value: 200, unit: 'mcg'),
};

/// Applies the FLTR-11a guardrail to a single warning given its
/// matching ingredient row. Returns [severityBelow] (monitor) when
/// the rule fires, else null (caller keeps the original severity).
///
/// Guardrail fires when ALL of:
///   * warning.severity.weight >= Severity.caution.weight (don't
///     touch monitor/informational/safe — already non-alarming)
///   * warning.severity.weight < Severity.contraindicated.weight
///     (never downgrade the worst tier — it's a hard stop)
///   * the ingredient's standard_name matches an entry in
///     [_lowDoseThresholds]
///   * the ingredient's quantity/unit match the threshold unit and
///     fall strictly below the threshold value
Severity? downgradeIfLowDose({
  required Severity severity,
  required Map<String, dynamic>? ingredient,
}) {
  if (ingredient == null) return null;
  // Leave informational/monitor/safe untouched — they're already
  // non-alarming. Also never downgrade contraindicated.
  if (severity.weight < Severity.caution.weight) return null;
  if (severity == Severity.contraindicated) return null;

  final name = ingredient['standard_name']?.toString().trim().toLowerCase();
  if (name == null || name.isEmpty) return null;
  final rule = _lowDoseThresholds[name];
  if (rule == null) return null;

  final qty = _asDouble(ingredient['quantity']);
  final unit = ingredient['unit']?.toString().trim().toLowerCase();
  if (qty == null || qty <= 0) return null;
  if (unit != rule.unit) return null;

  return qty < rule.value ? Severity.monitor : null;
}

/// Build a name → ingredient map for fast lookup in the warning
/// transform pass. Keyed on lowercased `standard_name` so it
/// matches the warning's `ingredient_name` after the same casing.
Map<String, Map<String, dynamic>> indexIngredientsByStandardName(
  List<Map<String, dynamic>> ingredients,
) {
  final out = <String, Map<String, dynamic>>{};
  for (final ing in ingredients) {
    final name = ing['standard_name']?.toString().trim().toLowerCase();
    if (name == null || name.isEmpty) continue;
    out[name] = ing;
  }
  return out;
}
