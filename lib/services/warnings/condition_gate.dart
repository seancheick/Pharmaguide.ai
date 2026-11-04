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

import 'package:pharmaguide/core/constants/consumer_disposition.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/units/dose_units.dart';
import 'package:pharmaguide/services/ingredients/elemental_form_dedupe.dart';
import 'package:pharmaguide/services/ingredients/ingredient_canonicalizer.dart';
import 'package:pharmaguide/services/ingredients/ingredient_row_fields.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart';

/// Single ingredient's dose entry as extracted from the detail blob.
typedef IngredientDose = ({double value, String unit});

/// Applies the pipeline-authored consumer disposition for the three-axis dose
/// contract. This gate performs no clinical interpretation or dose math.
///
/// `suppress` is the only hidden state. Known visible dispositions remain in
/// the stream for presentation routing. Missing or drifted values fail visible
/// so a schema mismatch cannot silently remove a potentially important result.
List<InteractionWarning> applyConsumerDispositionGate(
  List<InteractionWarning> warnings,
) {
  return warnings
      .where((warning) {
        final decision = warning.doseDecision;
        if (decision == null) return true;
        return consumerDispositionFromWire(decision.consumerDisposition) !=
            ConsumerDisposition.suppress;
      })
      .toList(growable: false);
}

/// Whether a dose rule that applies to this person went unread: the pipeline
/// suppressed it because it could not read the product's amount or form.
///
/// The disposition stands, so nothing is shown and no hazard is invented, but a
/// threshold nobody could read is not an all-clear. Callers report an incomplete
/// check. Who a rule applies to comes from its gate with the dose taken out,
/// since the dose is the part that could not be read, so a rule with no target
/// applies to every viewer.
bool hasUnreadDoseRule(
  Iterable<InteractionWarning> warnings, {
  required Set<String> userConditions,
  required Set<String> userDrugClasses,
  Set<String> userProfileFlags = const <String>{},
}) {
  const unread = {'amount_unknown', 'form_unknown'};
  final profile = UserProfile(
    conditions: userConditions,
    drugClasses: userDrugClasses,
    profileFlags: userProfileFlags,
  );
  return warnings.any((warning) {
    final decision = warning.doseDecision;
    if (decision == null ||
        !unread.contains(decision.evaluationStatus) ||
        warning.direction == 'beneficial' ||
        consumerDispositionFromWire(decision.consumerDisposition) !=
            ConsumerDisposition.suppress) {
      return false;
    }
    final gate = warning.profileGate;
    if (gate == null) {
      return warning.conditionIds.any(userConditions.contains) ||
          warning.drugClassIds.any(userDrugClasses.contains);
    }
    return evaluateProfileGate(
      {...gate, 'dose': null},
      profile,
      const ProductContext(),
    ).fires;
  });
}

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
        // The compact three-axis decision is authoritative. Do not reinterpret
        // it with the legacy severity-based floor contract.
        if (w.doseDecision != null) return true;
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
/// non-numeric dose values, and rows whose `skip_ul_check` leaves the amount
/// unreadable ([pipelineBlocksDoseRead]).
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
/// **One label row, one exposure (2026-11-03):** `ingredients` rows are per
/// serving and `rda_ul_data.analyzed_ingredients` rows are per day, and both
/// carry the label row's `raw_source_path` (see [_doseRows]). An analyzed row
/// replaces its `ingredients` mirror. When [isUsableDoseRow] then drops it, the
/// dose is gone under every name: no `ingredients` row carries `dose_role`, so
/// the mirror can't be left to count it. The mirror stays only if the analyzed
/// row has no dose to read, or carries a skip that blocks it. A row nested
/// above or below an analyzed row is the same dose seen as a form or a source
/// mass, so it no longer adds to the keys that analyzed row reports (328600:
/// 2000 mg Magtein under 144 mg Magnesium); it still counts toward its own
/// name. Only a path makes two rows one row. Rows with no path, from older
/// catalogs, fall back to matching canonical name + value + normalized unit.
Map<String, IngredientDose> extractIngredientDoses(
  Map<String, dynamic>? detailBlob,
) {
  final result = <String, IngredientDose>{};
  final blockedKeys = <String>{};
  if (detailBlob == null) return result;

  // Pass 1 — parse rows, dropping unusable ones and mirrored duplicates.
  final parsed = <_ParsedDoseRow>[];
  final seenSignatures = <String, bool>{};
  for (final (row: entry, :keys, :names, :blocked) in _doseRows(detailBlob)) {
    // Honor the SAME usability filter the stack summers enforce
    // ([isUsableDoseRow]): drop proprietary-blend containers, parent-total
    // roll-ups, inactive rows, and label-descriptor fragments. Previously
    // this gate skipped that filter and summed a nested-tree parent total
    // ON TOP of its children — a silent double-count that could push a
    // dose-dependent rule over (or fail to suppress below) its threshold.
    if (!isUsableDoseRow(entry)) continue;

    if (keys.isEmpty) continue;

    final primaryName = _primaryDoseName(entry);

    if (blocked) {
      parsed.add(
        _ParsedDoseRow(
          keys: keys,
          names: names,
          skip: true,
          value: 0,
          unit: '',
        ),
      );
      continue;
    }

    // Shared per-day-first readers ([readDoseAmount]/[readDoseUnit]): the
    // per-day-normalized fields win over raw per-serving `quantity`, and the
    // unit is folded to canonical spelling — identical to what the UL checker
    // and pairwise-threshold gate see for the same row.
    final value = readDoseAmount(entry);
    final unit = readDoseUnit(entry);
    if (value == null || unit.isEmpty) continue;

    // Older catalogs have no row path to join on, so a mirror can only be
    // recognized by its value. Rows with a path are distinct however equal they
    // look: [_doseRows] already joined the mirrors, and only the pipeline can
    // say a repeated row is a duplicate (206322: colostrum listed three times).
    if (primaryName != null) {
      final signature =
          '${canonicalizeIngredientName(primaryName)}|$value|$unit';
      final hasNoPath = _labelRowPath(entry) == null;
      final seenNoPath = seenSignatures[signature];
      if (seenNoPath != null && (hasNoPath || seenNoPath)) continue;
      seenSignatures[signature] = hasNoPath;
    }

    parsed.add(
      _ParsedDoseRow(
        keys: keys,
        names: names,
        skip: false,
        value: value,
        unit: unit,
      ),
    );
  }

  // Elemental vs compound dedup: collect, per key, whether any usable
  // row names the bare elemental nutrient for that key.
  final elementalKeys = <String>{};
  for (final row in parsed) {
    if (row.skip) continue;
    for (final key in row.keys) {
      if (row.isElemental(key)) elementalKeys.add(key);
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
          row.names.isNotEmpty &&
          !row.isElemental(key)) {
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
    required this.names,
    required this.skip,
    required this.value,
    required this.unit,
  });

  final Set<String> keys;

  /// The row's display names; a mirrored row has its mirror's as well, because
  /// the two arrays can spell one label row differently (Vitamin K / Vitamin K1).
  final Set<String> names;
  final bool skip;
  final double value;
  final String unit;

  bool isElemental(String key) =>
      names.any((name) => isElementalIngredientName(name, key));
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

typedef _DoseRow = ({
  Map<String, dynamic> row,
  Set<String> keys,
  Set<String> names,
  bool blocked,
});

_DoseRow _doseRow(
  Map<String, dynamic> row,
  Set<String> keys, {
  required bool blocked,
  Map<String, dynamic>? mirror,
}) => (
  row: row,
  keys: keys,
  names: {
    ?_primaryDoseName(row),
    if (mirror != null) ?_primaryDoseName(mirror),
  },
  blocked: blocked,
);

/// The blob's dose rows, each with the name keys it may add to.
List<_DoseRow> _doseRows(Map<String, dynamic> detailBlob) {
  final rdaUlData = detailBlob['rda_ul_data'];
  final analyzed = _rowMaps(
    rdaUlData is Map ? rdaUlData['analyzed_ingredients'] : null,
  );
  final analyzedByPath = <String, Map<String, dynamic>>{};
  final owners = <({String path, Set<String> keys})>[];
  for (final row in analyzed) {
    final path = _labelRowPath(row);
    if (path == null) continue;
    analyzedByPath[path] = row;
    // A row the total can't come from can't take the total from its branch.
    if (isUsableDoseRow(row) &&
        (readDoseAmount(row) ?? 0) > 0 &&
        readDoseUnit(row).isNotEmpty) {
      owners.add((path: path, keys: readDoseNameKeys(row)));
    }
  }

  final rows = <_DoseRow>[];
  final mirrors = <String, Map<String, dynamic>>{};
  for (final row in _rowMaps(detailBlob['ingredients'])) {
    // A skip that blocks the read covers every name, on whichever copy.
    if (pipelineBlocksDoseRead(row)) {
      rows.add(_doseRow(row, readDoseNameKeys(row), blocked: true));
      continue;
    }
    final path = _labelRowPath(row);
    final twin = analyzedByPath[path];
    if (twin == null || _lostItsDose(twin)) {
      rows.add(
        _doseRow(row, _keysNotOwnedOnBranch(row, owners), blocked: false),
      );
    } else if (isUsableDoseRow(twin)) {
      mirrors[path!] = row;
    }
  }
  // The mirror's names carry over: an analyzed row can spell fewer of them.
  for (final row in analyzed) {
    final mirror = mirrors[_labelRowPath(row)];
    rows.add(
      _doseRow(
        row,
        {
          ...readDoseNameKeys(row),
          if (mirror != null) ...readDoseNameKeys(mirror),
        },
        mirror: mirror,
        blocked: pipelineBlocksDoseReadOnLabel(row, analyzed),
      ),
    );
  }

  return rows;
}

/// A usable analyzed row with no amount or unit to read, and no pipeline reason
/// for it: a blocking skip reads no amount by design, and an unresolved unit is
/// the pipeline saying the printed quantity can't be read.
bool _lostItsDose(Map<String, dynamic> row) =>
    isUsableDoseRow(row) &&
    !pipelineBlocksDoseRead(row) &&
    !hasUnresolvedDoseUnit(row) &&
    (readDoseAmount(row) == null || readDoseUnit(row).isEmpty);

Set<String> _keysNotOwnedOnBranch(
  Map<String, dynamic> row,
  List<({String path, Set<String> keys})> owners,
) {
  final keys = readDoseNameKeys(row);
  final path = _labelRowPath(row);
  if (path == null) return keys;
  for (final owner in owners) {
    if (onSameLabelBranch(path, owner.path)) {
      keys.removeAll(owner.keys);
    }
  }
  return keys;
}

String? _labelRowPath(Map<String, dynamic> row) {
  final path = row['raw_source_path'];
  return path is String && path.trim().isNotEmpty ? path.trim() : null;
}

List<Map<String, dynamic>> _rowMaps(Object? rows) => rows is List
    ? [
        for (final row in rows.whereType<Map<Object?, Object?>>())
          Map<String, dynamic>.from(row),
      ]
    : const [];
