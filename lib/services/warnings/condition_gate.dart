// Pipeline-emitted warning gates and detail-blob dose extraction.
//
// The app no longer owns a condition-threshold table. Condition warning
// suppression is driven by pipeline-emitted metadata:
//   - `dose_floor_status == below|form_mismatch` for immaterial
//     dose-dependent warnings
//   - `direction == beneficial` for condition benefits that should not show as
//     monitor/caution warnings
//
// The dose extraction helper stays here because product health facts and stack
// aggregation still need a conservative canonical dose map from detail blobs.

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/units/dose_units.dart';
import 'package:pharmaguide/services/ingredients/ingredient_canonicalizer.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';

/// Single ingredient's dose entry as extracted from the detail blob.
typedef IngredientDose = ({double value, String unit});

/// Shared dose-suppression guardrail (G3) for BOTH dose gates — the
/// emitted-floor condition gate below AND the pairwise structured-threshold
/// gate in `stack_interaction_checker.dart`.
///
/// A warning is ELIGIBLE to be dose-suppressed only when it is a
/// non-beneficial, dose-dependent rule that is NOT a hard
/// (contraindicated / avoid) warning. The caller still supplies the dose
/// SIGNAL (an emitted `dose_floor_status`, or a live threshold comparison);
/// this only encodes the severity/direction/materiality invariant.
///
/// Centralised on purpose: the pairwise gate used to carry its own weaker
/// copy that omitted the hard-severity check, so a below-threshold
/// contraindicated interaction could be silently dropped. One predicate means
/// the two gates can never drift apart again.
///
/// Takes the RAW pipeline severity string (not a parsed [Severity]) so it can
/// fail safe at the parse boundary. Returns `false` (NOT suppressible → the
/// warning FIRES) for:
///   - materiality != dose_dependent (presence-matters / unknown),
///   - direction == beneficial (a benefit, handled by the beneficial gate),
///   - severity contraindicated / avoid,
///   - an UNKNOWN / MISSING severity token — fail-safe: a severity the app
///     can't recognize is never dose-hidden. `Severity.fromString` coerces
///     unknown strings to `caution` (suppressible); a future OTA vocab drift
///     (as just happened to EvidenceLevel) or an omitted field must not let a
///     possibly-serious row be silently dropped.
/// Unknown / null direction is treated as non-beneficial and stays suppressible
/// once the dose signal says below-floor (the dose signal is the authority).
bool doseSuppressionGuardsPass({
  required String? severityRaw,
  required String? direction,
  required String? materiality,
}) {
  if (materiality?.trim().toLowerCase() != 'dose_dependent') return false;
  if (direction?.trim().toLowerCase() == 'beneficial') return false;
  final raw = severityRaw?.trim() ?? '';
  if (raw.isEmpty || !Severity.isKnownString(raw)) return false;
  if (Severity.fromString(raw).isHard) return false;
  return true;
}

/// Emitted-floor dose gate (smart-flagging, pipeline batch diabetes-01+).
///
/// Drops warnings the pipeline has already marked immaterial at THIS product's
/// dose/form: a non-beneficial, dose-dependent rule whose form-scoped
/// `min_effective_dose` evaluated to `dose_floor_status == "below"` or
/// `"form_mismatch"`. Emitted-first — it reads the pipeline's precomputed
/// status (no dose math here).
///
/// Runs BEFORE the profile-visibility filter so a below-floor row can never be
/// promoted back by a profile match (guardrail G2).
///
/// Narrow by design (guardrail G3): suppress ONLY when
///   direction != beneficial ∧ materiality == dose_dependent ∧
///   dose_floor_status in {below, form_mismatch} ∧ severity is not a hard
///   override.
/// Everything else FIRES — missing/unknown floor status (fail open), unknown
/// form (pipeline emits null there), and contraindicated/avoid (a hard warning
/// is never dose-suppressed).
List<InteractionWarning> applyEmittedFloorGate(
  List<InteractionWarning> warnings,
) {
  const suppressibleStatuses = {'below', 'form_mismatch'};
  return warnings
      .where((w) {
        if (!suppressibleStatuses.contains(w.doseFloorStatus)) return true;
        if (!doseSuppressionGuardsPass(
          severityRaw: w.severityRaw,
          direction: w.direction,
          materiality: w.materiality,
        )) {
          return true;
        }
        return false;
      })
      .toList(growable: false);
}

/// Emitted-beneficial suppression.
///
/// The pipeline tags condition warnings for beneficial nutrients with
/// `direction == 'beneficial'` (e.g. "Vitamin D3 / ttc"). A monitor/caution flag
/// for a nutrient that HELPS the condition is the boy-who-cried-wolf false
/// positive the const `positive` table suppresses; this reads the pipeline's own
/// `direction` instead, so the suppression survives the table's removal.
///
/// Same narrow guardrail as [applyEmittedFloorGate] (G3): never suppress a hard
/// warning (contraindicated / avoid) even if tagged beneficial — a directional
/// contradiction fails safe toward warning. Everything non-beneficial FIRES,
/// including null / unknown direction (fail open).
///
/// Runs before profile filtering so a beneficial row can't be promoted back by
/// a matching profile.
List<InteractionWarning> applyEmittedBeneficialGate(
  List<InteractionWarning> warnings,
) {
  return warnings
      .where((w) {
        if (w.direction != 'beneficial') return true;
        if (w.severity.isHard) return true;
        return false;
      })
      .toList(growable: false);
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
/// threshold-gate era — `extractIngredientDoses` returned an empty map for
/// live products, so dose-aware entries always fail-safe-fired. Live
/// walkthrough caught it via PureLean's ALA + Vanadium false positives
/// (sub-clinical doses still firing).
/// Also accepts the legacy `dose_amount` / `dose_unit` shape so
/// hand-crafted test fixtures (and any old cached blobs) still gate.
///
/// When the same canonical key appears twice, safely comparable doses
/// are summed. Exact unit matches and simple mass units (`g`/`mg`/`mcg`)
/// are comparable. Incompatible duplicate units remove the key entirely
/// so downstream dose consumers fail safe instead of making a false-precision
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
          '|$value|${normalizeDoseUnit(rawUnit)}';
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

      final converted = amountInMass(
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
