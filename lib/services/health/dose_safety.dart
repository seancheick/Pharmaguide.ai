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
library;

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
/// no widget/ref dependencies, so the logic is unit-testable in isolation.
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
  if (_hasConfirmedUlExceedance(entry, ingredient: ingredient)) {
    return DoseSafety.exceedsUl;
  }
  if (_hasStructuredUlDecision(entry)) return DoseSafety.withinLimits;

  // Per the FLTR-11 clarification: compare the actual disclosed
  // `quantity` against the UL, NOT `per_day_max`. per_day_max is a
  // pipeline-normalized scaling field (quantity × max servings/day)
  // used for stack aggregation. Using it would double-count the
  // serving math and fire false-positive UL alerts on any product
  // whose label allows multiple servings.
  return _quantityExceedsResolvedUl(entry, ingredient: ingredient)
      ? DoseSafety.exceedsUl
      : DoseSafety.withinLimits;
}

bool _hasConfirmedUlExceedance(
  Map<String, dynamic> entry, {
  Map<String, dynamic>? ingredient,
}) {
  if (entry['skip_ul_check'] == true) return false;

  final overUl = entry['over_ul'];
  if (overUl == true) return true;
  if (overUl == false) return false;

  final pctUl = _asDouble(entry['pct_ul']);
  if (pctUl != null) return pctUl > 100.0;

  if (_hasStructuredUlDecision(entry)) return false;

  return _quantityExceedsResolvedUl(entry, ingredient: ingredient);
}

bool _hasStructuredUlDecision(Map<String, dynamic> entry) {
  return entry.containsKey('over_ul') || entry.containsKey('pct_ul');
}

bool _quantityExceedsResolvedUl(
  Map<String, dynamic> entry, {
  Map<String, dynamic>? ingredient,
}) {
  final quantity =
      _asDouble(entry['quantity']) ?? _asDouble(ingredient?['quantity']);
  if (quantity == null || quantity <= 0) return false;

  // UL resolution order honoring the pipeline contract:
  //   1. ul_for_default_profile — age/sex-aware UL when the pipeline
  //      resolved one for the anonymous default (adult 19-30).
  //   2. highest_ul — worst-case UL across demographics, used when
  //      the pipeline couldn't resolve a profile-specific UL.
  final ul =
      _asDouble(entry['ul_for_default_profile']) ??
      _asDouble(entry['highest_ul']);
  if (ul == null || ul <= 0) return false;

  // Unit reconciliation (P2 hardening). `quantity` is in the disclosed
  // `unit`; the UL is expressed in the nutrient's reference unit
  // (`nutrient_unit`, falling back to `converted_unit`). Comparing them raw
  // is a medical-grade defect: Boron 150 mcg vs a 20 mg UL would read
  // 150 > 20 → a false exceedance. Convert the quantity into the UL's unit
  // when both are simple metric mass; when the UL unit is absent (older
  // blobs) assume it already matches the disclosed unit (legacy behavior);
  // when the units differ and cannot be reconciled (e.g. IU ↔ mg, which is
  // form-dependent) NEVER guess — decline to flag.
  final quantityUnit = (entry['unit'] ?? ingredient?['unit'] ?? '').toString();
  final ulUnit =
      (entry['nutrient_unit'] ?? entry['converted_unit'] ?? '').toString();
  final comparableQuantity = _quantityInUlUnit(
    quantity,
    quantityUnit: quantityUnit,
    ulUnit: ulUnit,
  );
  if (comparableQuantity == null) return false;

  return comparableQuantity > ul;
}

/// Convert [quantity] (in [quantityUnit]) into [ulUnit] for comparison
/// against the resolved UL. Returns null when the units differ and cannot
/// be safely reconciled, so the caller declines to flag rather than compare
/// across incompatible units.
double? _quantityInUlUnit(
  double quantity, {
  required String quantityUnit,
  required String ulUnit,
}) {
  final from = _normalizeUnit(quantityUnit);
  final to = _normalizeUnit(ulUnit);
  // No UL unit disclosed (or no quantity unit) → assume same reference unit,
  // matching the historical same-unit comparison.
  if (from.isEmpty || to.isEmpty || from == to) return quantity;

  final fromGrams = _simpleMassGramsFactor(from);
  final toGrams = _simpleMassGramsFactor(to);
  if (fromGrams == null || toGrams == null) return null;
  return quantity * fromGrams / toGrams;
}

String _normalizeUnit(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll('µg', 'mcg')
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

double? _simpleMassGramsFactor(String unit) {
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
  return s.isEmpty ? null : _ulNutrientKey(s);
}

/// A single per-ingredient UL exceedance surfaced by the pipeline's
/// `rda_ul_data.analyzed_ingredients[]` array. The row must carry a
/// structured UL exceedance decision; warning text alone is not trusted.
class UlExceedance {
  final String standardName;
  final String warning;
  const UlExceedance({required this.standardName, required this.warning});
}

/// Extract UL-exceedance alerts from the pipeline's analysis block.
///
/// Respects the same [skip_ul_check] contract as [resolveDoseSafety]:
/// when the pipeline opts out of UL evaluation, no alert surfaces.
/// Entries with no structured exceedance, no warning strings, no
/// standard_name, or a malformed warnings field are skipped. Empty list
/// when [ulAnalysis] is null or carries no exceedances.
List<UlExceedance> extractUlExceedances(List<dynamic>? ulAnalysis) {
  if (ulAnalysis == null || ulAnalysis.isEmpty) return const [];
  final out = <UlExceedance>[];
  final seenNutrients = <String>{};
  for (final rawEntry in ulAnalysis) {
    final entry = _asStringKeyMap(rawEntry);
    if (entry == null) continue;
    if (entry['skip_ul_check'] == true) continue;
    if (!_hasConfirmedUlExceedance(entry)) continue;
    final rawName = entry['standard_name'] ?? entry['ingredient'];
    final name = rawName?.toString().trim();
    if (name == null || name.isEmpty) continue;
    final warnings = entry['warnings'];
    if (warnings is! List) continue;
    final messages = <String>[];
    for (final w in warnings) {
      final msg = w?.toString().trim() ?? '';
      if (msg.isEmpty) continue;
      messages.add(msg);
    }
    if (messages.isEmpty) continue;
    if (!seenNutrients.add(_ulNutrientKey(name))) continue;
    for (final msg in messages) {
      out.add(UlExceedance(standardName: name, warning: msg));
    }
  }
  return out;
}

Map<String, dynamic>? _asStringKeyMap(Object? raw) {
  if (raw is! Map) return null;
  final out = <String, dynamic>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is String) out[key] = entry.value;
  }
  return out.isEmpty ? null : out;
}

String _ulNutrientKey(String name) {
  final normalized = name.trim().toLowerCase();
  final compact = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  if (RegExp(
    r'\b(vitamin d2|vitamin d3|vitamin d|cholecalciferol|ergocalciferol)\b',
  ).hasMatch(compact)) {
    return 'vitamin d';
  }
  return compact.trim();
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
