// Condition-tagged warning gate.
//
// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.1, T4.
//
// T3 built the (condition × ingredient) threshold table. T4 (this
// file) is the consumer that runs every condition-tagged pipeline
// warning through the table and drops the ones that shouldn't fire:
//
//   - directionality: positive → suppress unconditionally (vitamin D
//     for TTC: it's beneficial, never warn)
//   - dose < minDose            → suppress (caffeine 50 mg for
//     hypertension: under the 200 mg trigger)
//
// What stays:
//   - warnings with no condition tag                  (untagged → fire)
//   - condition-tagged warnings with no ingredient    (can't gate → fire)
//   - condition-tagged warnings with no table entry   (no rule → fire)
//   - dose missing / unit mismatch                     (fail-safe → fire)
//   - any condition in a multi-condition warning that
//     fires above threshold or has no entry            (any-fires-keeps)
//
// The fail-safe defaults are deliberate. We're medical-grade. When in
// doubt, surface the warning — over-warning is recoverable, missed
// warnings are not. The whole point of the threshold table is to
// scope down false positives where we have explicit evidence that the
// dose is below clinical relevance OR the nutrient is positive for
// the condition.

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/warnings/condition_thresholds.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

/// Single ingredient's dose entry as extracted from the detail blob.
typedef IngredientDose = ({double value, String unit});

/// Emitted-floor dose gate (smart-flagging, pipeline batch diabetes-01+).
///
/// Drops warnings the pipeline has already marked immaterial at THIS product's
/// dose: a harmful, dose-dependent rule whose form-scoped `min_effective_dose`
/// evaluated to `dose_floor_status == "below"`. Emitted-first — it reads the
/// pipeline's precomputed status (no dose math here); [applyConditionThresholdGate]
/// stays the fallback for rules carrying a const-table entry instead.
///
/// Runs BEFORE the profile-visibility filter so a below-floor row can never be
/// promoted back by a profile match (guardrail G2).
///
/// Narrow by design (guardrail G3): suppress ONLY when
///   direction == harmful ∧ materiality == dose_dependent ∧
///   dose_floor_status == below ∧ severity is not a hard override.
/// Everything else FIRES — missing/unknown floor status (fail open), unknown
/// form (pipeline emits null there), and contraindicated/avoid (a hard warning
/// is never dose-suppressed).
List<InteractionWarning> applyEmittedFloorGate(
  List<InteractionWarning> warnings,
) {
  return warnings.where((w) {
    if (w.doseFloorStatus != 'below') return true;
    if (w.direction != 'harmful') return true;
    if (w.materiality != 'dose_dependent') return true;
    if (w.severity == Severity.contraindicated ||
        w.severity == Severity.avoid) {
      return true;
    }
    return false;
  }).toList(growable: false);
}

/// Build a `canonical-ingredient-name → (dose, unit)` map from the
/// pipeline's product-detail dose rows. Prefer the pipeline's
/// `rda_ul_data.analyzed_ingredients` rows when present because they
/// carry the same evaluated ingredient identity used by stack/UL
/// logic. Skips entries missing name / dose / unit, entries with
/// non-numeric dose values, and rows the pipeline marked unsafe for
/// evaluation (`skip_ul_check == true`).
///
/// Pipeline blob shape (from live data — verified 2026-04-30):
/// ```
/// 'ingredients': [
///   {'name': 'Magnesium', 'quantity': 200, 'unit': 'mg'},
///   {'name': 'Vitamin D', 'quantity': 1000, 'unit': 'IU'},
/// ]
/// ```
///
/// **T16.2b (2026-04-30) — field-name fix:** pre-T16.2b this read
/// `dose_amount` + `dose_unit` (the names in an old pipeline draft
/// spec). Live pipeline ships `quantity` + `unit`, matching what the
/// rendering side has always used (see `product_detail_screen.dart`
/// `_CollapsibleIngredients` row builder, `ingredient_sort.dart`,
/// `services/health/dose_safety.dart`). The mismatch silently broke every `aboveDose`
/// threshold gate since T3/T4 shipped — `extractIngredientDoses`
/// returned an empty map for live products, so dose-gated entries
/// always fail-safe-fired. Live walkthrough caught it via PureLean's
/// ALA + Vanadium false positives (sub-clinical doses still firing).
/// Also accepts the legacy `dose_amount` / `dose_unit` shape so
/// hand-crafted test fixtures (and any old cached blobs) still gate.
///
/// When the same canonical key appears twice, safely comparable doses
/// are summed. Exact unit matches and simple mass units (`g`/`mg`/`mcg`)
/// are comparable. Incompatible duplicate units remove the key entirely
/// so threshold gates fail safe instead of making a false-precision
/// comparison.
///
/// **Elemental vs compound dedup (2026-06-12):** verified pipeline bug
/// (dsld_id 315678, 'Magnesium Glycinate 400 mg') — the blob carries TWO
/// rows mapping to the same canonical nutrient: {'Magnesium', 60 mg}
/// (elemental, the label-declared total) and {'Magnesium Glycinate',
/// 400 mg} (compound weight). Summing both yields 460 mg of "magnesium"
/// and false UL/threshold breaches. Within ONE blob: when a key has a
/// bare-elemental-named row (name equals the key, directly or after
/// stripping a parenthetical), compound-named rows do NOT contribute to
/// that key (they still contribute to their own compound-name key).
/// Multi-form labels with no bare elemental row ('Magnesium (as oxide)'
/// + 'Magnesium (as citrate)') still sum — both names strip to the
/// elemental name, so neither is a compound duplicate.
///
/// **Mirrored-row dedup (2026-06-12):** `_doseRows` concatenates
/// `ingredients` and `rda_ul_data.analyzed_ingredients`, and live blobs
/// (315678) carry the SAME rows in both arrays. Rows whose canonical
/// name + value + normalized unit match an already-seen row are treated
/// as the same label row and counted once.
Map<String, IngredientDose> extractIngredientDoses(
  Map<String, dynamic>? detailBlob,
) {
  final result = <String, IngredientDose>{};
  final blockedKeys = <String>{};
  if (detailBlob == null) return result;

  // Pass 1 — parse rows, dropping unusable ones and mirrored duplicates.
  final parsed = <_ParsedDoseRow>[];
  final seenSignatures = <String>{};
  for (final entry in _doseRows(detailBlob)) {
    final keys = _doseNameKeys(entry);
    if (keys.isEmpty) continue;

    final primaryName = _primaryDoseName(entry);

    if (entry['skip_ul_check'] == true) {
      parsed.add(
        _ParsedDoseRow(
          keys: keys,
          primaryName: primaryName,
          skip: true,
          value: 0,
          unit: '',
        ),
      );
      continue;
    }

    // Live pipeline uses `quantity` / `unit` or `daily_amount_unit`.
    // Legacy spec / hand-built fixtures use `dose_amount` / `dose_unit`.
    // Try evaluated live names first; fall through to legacy on null.
    final rawAmount =
        entry['quantity'] ??
        entry['dose_amount'] ??
        entry['converted_quantity'] ??
        entry['amount'] ??
        entry['per_day_max'];
    final rawUnit =
        (entry['daily_amount_unit'] ??
                entry['unit'] ??
                entry['dose_unit'] ??
                entry['normalized_unit'])
            ?.toString();
    if (rawAmount == null || rawUnit == null || rawUnit.trim().isEmpty) {
      continue;
    }

    final value = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse(rawAmount.toString());
    if (value == null || !value.isFinite) continue;

    // Mirrored-row dedup: the same label row shipped in both
    // `ingredients` and `rda_ul_data.analyzed_ingredients`.
    if (primaryName != null) {
      final signature =
          '${canonicalizeIngredientName(primaryName)}'
          '|$value|${_normalizeDoseUnit(rawUnit)}';
      if (!seenSignatures.add(signature)) continue;
    }

    parsed.add(
      _ParsedDoseRow(
        keys: keys,
        primaryName: primaryName,
        skip: false,
        value: value,
        unit: rawUnit.trim(),
      ),
    );
  }

  // Elemental vs compound dedup: collect, per key, whether any usable
  // row names the bare elemental nutrient for that key.
  final elementalKeys = <String>{};
  for (final row in parsed) {
    if (row.skip || row.primaryName == null) continue;
    for (final key in row.keys) {
      if (_isElementalDoseName(row.primaryName!, key)) {
        elementalKeys.add(key);
      }
    }
  }

  // Pass 2 — original summing semantics, minus compound duplicates.
  for (final row in parsed) {
    if (row.skip) {
      for (final key in row.keys) {
        result.remove(key);
        blockedKeys.add(key);
      }
      continue;
    }

    for (final key in row.keys) {
      if (blockedKeys.contains(key)) continue;

      // The key has a bare elemental row and this row is a compound
      // form — the elemental row is the label-declared total for this
      // key. Skip the compound contribution (it still counts toward
      // its own compound-name key).
      if (elementalKeys.contains(key) &&
          row.primaryName != null &&
          !_isElementalDoseName(row.primaryName!, key)) {
        continue;
      }

      final existing = result[key];
      if (existing == null) {
        result[key] = (value: row.value, unit: row.unit);
        continue;
      }

      final converted = _amountInUnit(
        row.value,
        from: row.unit,
        to: existing.unit,
      );
      if (converted == null) {
        result.remove(key);
        blockedKeys.add(key);
        continue;
      }

      result[key] = (value: existing.value + converted, unit: existing.unit);
    }
  }

  return result;
}

class _ParsedDoseRow {
  const _ParsedDoseRow({
    required this.keys,
    required this.primaryName,
    required this.skip,
    required this.value,
    required this.unit,
  });

  final Set<String> keys;
  final String? primaryName;
  final bool skip;
  final double value;
  final String unit;
}

/// The label-facing display name of a dose row — used for elemental
/// detection. Canonical-id-ish fields (`mapped_name`, `canonical_id`)
/// are intentionally NOT consulted here: a compound row often carries
/// the elemental canonical id, which is exactly the double-count.
String? _primaryDoseName(Map<String, dynamic> entry) {
  for (final field in const ['standard_name', 'name', 'ingredient']) {
    final raw = entry[field]?.toString().trim();
    if (raw != null && raw.isNotEmpty) return raw;
  }
  return null;
}

/// True when [rawName] is the bare elemental nutrient name for the
/// canonical [key]: canonicalizes to the key directly ('Magnesium' →
/// 'magnesium'), or after stripping a parenthetical ('Magnesium
/// (elemental)', 'Magnesium (as oxide)'). Conservative: any other name
/// is a distinct (compound) form.
bool _isElementalDoseName(String rawName, String key) {
  if (canonicalizeIngredientName(rawName) == key) return true;
  final stripped = rawName.replaceAll(RegExp(r'\([^)]*\)'), ' ').trim();
  if (stripped.isEmpty || stripped == rawName.trim()) return false;
  return canonicalizeIngredientName(stripped) == key;
}

double? _amountInUnit(
  double amount, {
  required String from,
  required String to,
}) {
  final normalizedFrom = _normalizeDoseUnit(from);
  final normalizedTo = _normalizeDoseUnit(to);
  if (normalizedFrom.isEmpty || normalizedTo.isEmpty) return null;
  if (normalizedFrom == normalizedTo) return amount;

  final fromGrams = _simpleMassGramsFactor(normalizedFrom);
  final toGrams = _simpleMassGramsFactor(normalizedTo);
  if (fromGrams == null || toGrams == null) return null;
  return amount * fromGrams / toGrams;
}

double? _simpleMassGramsFactor(String unit) {
  return switch (unit) {
    'g' || 'gram' || 'grams' || 'gram(s)' => 1.0,
    'mg' => 0.001,
    'mcg' || 'microgram' || 'micrograms' => 0.000001,
    _ => null,
  };
}

String _normalizeDoseUnit(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll('µg', 'mcg')
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

List<Map<String, dynamic>> _doseRows(Map<String, dynamic> detailBlob) {
  final rows = <Map<String, dynamic>>[];

  final ingredients = detailBlob['ingredients'];
  if (ingredients is List) {
    rows.addAll(
      ingredients.whereType<Map<Object?, Object?>>().map(
        (entry) => Map<String, dynamic>.from(entry),
      ),
    );
  }

  final rdaUlData = detailBlob['rda_ul_data'];
  if (rdaUlData is Map) {
    final analyzed = rdaUlData['analyzed_ingredients'];
    if (analyzed is List) {
      rows.addAll(
        analyzed.whereType<Map<Object?, Object?>>().map(
          (entry) => Map<String, dynamic>.from(entry),
        ),
      );
    }
  }

  return rows;
}

Set<String> _doseNameKeys(Map<String, dynamic> entry) {
  final keys = <String>{};
  for (final field in const [
    'standard_name',
    'name',
    'ingredient',
    'mapped_name',
    'canonical_id',
    'normalized_key',
  ]) {
    final raw = entry[field]?.toString();
    if (raw == null || raw.trim().isEmpty) continue;
    final canonical = canonicalizeIngredientName(raw);
    if (canonical.isNotEmpty) keys.add(canonical);
  }
  return keys;
}

/// Apply per-condition threshold gating to a list of pipeline-emitted
/// warnings. Returns the warnings that should still surface.
///
/// **Multi-condition warnings:** suppress only when EVERY tagged
/// condition is gated for the warning's ingredient (positive OR
/// below threshold). If ANY tagged condition still fires (no entry,
/// dose at/above threshold, missing dose, unit mismatch), the warning
/// keeps firing. Medical-grade conservative — better to over-warn
/// than miss a real risk.
///
/// **Pure function** — no Riverpod, no DB, no Flutter framework deps.
/// Trivial to unit-test against fixtures of `InteractionWarning`.
List<InteractionWarning> applyConditionThresholdGate({
  required List<InteractionWarning> warnings,
  required Map<String, IngredientDose> ingredientDoses,
}) {
  return warnings
      .where(
        (w) => !_isFullyGated(warning: w, ingredientDoses: ingredientDoses),
      )
      .toList(growable: false);
}

/// T4 follow-up (2026-04-29) — gate the `interaction_summary` blob,
/// not just the `warnings` list. The pipeline emits a SECOND surface
/// (`interaction_summary.condition_summary`) that the screen renders
/// directly via `_InteractionConditionDetails`, completely bypassing
/// `applyConditionThresholdGate`. That's how Sean's live walkthrough
/// found "Diabetes — MONITOR / Affected by: Vitamin D" rendering for
/// a Vit D 1000 IU product even though T4 had supposedly suppressed
/// the false positive.
///
/// This helper:
///   - Filters each condition's `ingredients` list, removing names
///     that are `positive` for that condition (e.g., Vit D for
///     diabetes, magnesium for hypertension).
///   - Drops the condition entry entirely when no ingredients survive
///     (the only reason to surface the condition was the positive
///     nutrients we just suppressed).
///   - Leaves `drug_class_summary` untouched — drug-class warnings
///     don't have positive-directional nutrients in the same way.
///   - Returns null when input is null (screen-level guard).
///   - Returns a NEW map; never mutates the input.
///
/// **T16.2e (2026-04-30) — dose-gating extension:** when callers pass
/// [ingredientDoses] (the same map T4's main gate uses), this surface
/// also applies dose-threshold gating per-ingredient. Pre-T16.2e the
/// `condition_summary` shape couldn't dose-gate, so sub-clinical doses
/// of `aboveDose`-tagged nutrients leaked through (e.g., PureLean's
/// ALA 350 mg / Vanadium 50 mcg / Niacin 37.5 mg all surfaced as
/// "Diabetes — caution — affected by …" while T4's warnings-list gate
/// had already suppressed the underlying inline warnings). The
/// resulting cross-surface contradiction (§7 §8 mismatch) was Sean's
/// PureLean walkthrough finding, 2026-04-30.
///
/// Same fail-safe semantics as `_isFullyGated`: drop only when we have
/// positive evidence (entry exists + dose known + units match + dose
/// below threshold). Anything unknown — no entry, no dose, unit
/// mismatch — keeps the ingredient. When [ingredientDoses] is null,
/// behavior matches pre-T16.2e (positive-only filtering).
Map<String, dynamic>? gateInteractionSummary(
  Map<String, dynamic>? summary, {
  Map<String, IngredientDose>? ingredientDoses,
}) {
  if (summary == null) return null;

  final conditionSummaryRaw =
      summary['condition_summary'] as Map<String, dynamic>?;
  if (conditionSummaryRaw == null || conditionSummaryRaw.isEmpty) {
    // No condition-side data → nothing to gate. Pass through.
    return summary;
  }

  final filteredConditions = <String, dynamic>{};

  for (final entry in conditionSummaryRaw.entries) {
    final conditionId = entry.key;
    final data = entry.value;
    if (data is! Map<String, dynamic>) {
      // Defensive — unexpected shape. Pass through.
      filteredConditions[conditionId] = data;
      continue;
    }

    final ingredientsRaw = data['ingredients'];
    if (ingredientsRaw is! List) {
      // No ingredient binding → can't gate, pass through.
      filteredConditions[conditionId] = data;
      continue;
    }

    final ingredients = ingredientsRaw
        .map((i) => i.toString())
        .toList(growable: false);
    final survivors = <String>[];
    for (final ing in ingredients) {
      final entry = lookupConditionThreshold(
        conditionId: conditionId,
        ingredientName: ing,
      );

      // Drop when explicitly positive for the condition (Vit D for
      // diabetes, magnesium for hypertension, etc).
      if (entry?.directionality == NutrientDirectionality.positive) {
        continue;
      }

      // T16.2e (2026-04-30) — dose-gate `aboveDose` neutral entries
      // when the caller provided ingredient doses. Same fail-safe
      // pattern as `_isFullyGated`: drop only when entry exists, dose
      // is known, units match, and dose is strictly below threshold.
      // Anything unknown (no entry, missing dose, unit mismatch) keeps
      // the ingredient — over-warn is recoverable, miss is not.
      if (entry != null &&
          entry.directionality == NutrientDirectionality.neutral &&
          ingredientDoses != null &&
          entry.minDose != null &&
          entry.doseUnit != null) {
        final canonical = canonicalizeIngredientName(ing);
        final dose = ingredientDoses[canonical];
        if (dose != null &&
            entry.doseUnit!.toLowerCase() == dose.unit.toLowerCase() &&
            dose.value < entry.minDose!) {
          continue;
        }
      }

      survivors.add(ing);
    }

    if (survivors.isEmpty) {
      // Every ingredient was positive for this condition → the only
      // reason this condition surfaced was the positives. Drop it.
      continue;
    }

    // Keep the condition entry with the filtered ingredient list.
    filteredConditions[conditionId] = {...data, 'ingredients': survivors};
  }

  return {...summary, 'condition_summary': filteredConditions};
}

/// Compute the highest severity AMONG warnings that match the user's
/// profile.
///
/// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T16.2a
/// (medical-grade-accuracy bundle, 2026-04-30).
///
/// **Why this exists** — pre-T16.2a the `_ConditionAlertBanner`
/// banner used `interaction_summary.highest_severity` for its title
/// copy. That field is the OVERALL highest severity across ALL
/// warnings on the product, including ones that don't match the
/// user's profile. Sean's PureLean walkthrough caught the bug:
///   - Pipeline `highest_severity = 'avoid'` (from a general
///     precaution flagged regardless of user profile)
///   - User has Diabetes → matched warnings: ALA caution + Vanadium
///     monitor (no avoid)
///   - Banner displayed: "Avoid — relevant to your profile"
///   - §7 actually showed: caution + monitor
/// → mismatched copy / boy-who-cried-wolf erosion of trust.
///
/// This helper walks the gated `condition_summary` and
/// `drug_class_summary` and reads `highest_severity` per entry,
/// keeping only entries whose key matches [matchedConditionIds] or
/// [matchedDrugClassIds]. Returns the max severity name (lowercase).
/// Falls back to [fallback] when no matched entry has a usable
/// severity (defensive — caller shouldn't crash on pipeline drift).
String computeMatchedHighestSeverity({
  required Map<String, dynamic>? gatedSummary,
  required List<String> matchedConditionIds,
  required List<String> matchedDrugClassIds,
  required String fallback,
}) {
  if (gatedSummary == null) return fallback;

  Severity max = Severity.safe;
  bool anyMatched = false;

  void considerEntry(Map<String, dynamic> bucket, String id) {
    final data = bucket[id];
    if (data is! Map<String, dynamic>) return;
    final raw = data['highest_severity']?.toString().toLowerCase().trim();
    if (raw == null || raw.isEmpty) return;
    final sev = Severity.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => Severity.safe,
    );
    if (sev.weight > max.weight) max = sev;
    anyMatched = true;
  }

  final conditionSummary =
      gatedSummary['condition_summary'] as Map<String, dynamic>?;
  if (conditionSummary != null) {
    for (final id in matchedConditionIds) {
      considerEntry(conditionSummary, id);
    }
  }

  final drugClassSummary =
      gatedSummary['drug_class_summary'] as Map<String, dynamic>?;
  if (drugClassSummary != null) {
    for (final id in matchedDrugClassIds) {
      considerEntry(drugClassSummary, id);
    }
  }

  if (!anyMatched) return fallback;
  return max.name;
}

/// Returns `true` when EVERY condition tagged on the warning is gated
/// (positive OR below dose threshold) for the warning's ingredient.
/// Returns `false` (= keep the warning) on any of:
///   - empty conditionIds
///   - missing ingredientName
///   - condition with no table entry (unknown rule → fire)
///   - missing dose for the ingredient (can't compare → fire)
///   - unit mismatch between threshold and dose (fail-safe → fire)
///   - dose >= minDose for any condition (above threshold → fire)
bool _isFullyGated({
  required InteractionWarning warning,
  required Map<String, IngredientDose> ingredientDoses,
}) {
  // No condition tag → not subject to condition gating.
  if (warning.conditionIds.isEmpty) return false;

  final ingredientName = warning.ingredientName;
  if (ingredientName == null || ingredientName.trim().isEmpty) {
    // Condition-tagged but ingredient unknown — can't reason about
    // dose. Conservatively fire.
    return false;
  }

  final canonicalIngredient = canonicalizeIngredientName(ingredientName);
  final dose = ingredientDoses[canonicalIngredient];

  for (final rawCondition in warning.conditionIds) {
    final entry = lookupConditionThreshold(
      conditionId: rawCondition,
      ingredientName: ingredientName,
    );

    // No table entry for (condition, ingredient) → fall through to
    // existing pipeline behavior (fire). Suppression requires positive
    // evidence in the table — the table is opt-in, never opt-out.
    if (entry == null) return false;

    if (entry.directionality == NutrientDirectionality.positive) {
      // Beneficial — suppress for this condition; check the next one.
      continue;
    }

    // Neutral entry: gate by dose vs threshold.
    if (dose == null) {
      // No dose data for this ingredient — fail-safe fire.
      return false;
    }
    if (entry.doseUnit == null) {
      // Defensive — `aboveDose` ctor always sets doseUnit. If a
      // future entry skips it, fail-safe fire.
      return false;
    }
    if (entry.doseUnit!.toLowerCase() != dose.unit.toLowerCase()) {
      // Unit mismatch (e.g., threshold IU vs label mcg) — fail-safe
      // fire. Backlog: per-nutrient unit normalization (mcg ↔ IU
      // for vitamin A retinol, mcg ↔ IU for vitamin D, etc.).
      return false;
    }
    if (entry.minDose == null || dose.value < entry.minDose!) {
      // Below clinical-meaningful trigger — suppress for this
      // condition; check the next one.
      continue;
    }
    // Dose at or above threshold — fire.
    return false;
  }

  // Every tagged condition was gated (positive OR below threshold)
  // → suppress the warning entirely.
  return true;
}
