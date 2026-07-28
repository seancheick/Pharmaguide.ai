import 'dart:convert';

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';

enum InteractionType {
  drugSupplement,
  supplementSupplement,
  drugDrug,
  conditionSupplement,
}

enum InteractionSource { pipeline, stackEngine, aiChat }

/// Pharmacological effect direction for an interaction.
///
/// Mirrors the `effect_type` column the M2 pipeline writes into the
/// bundled `interactions` table (spec §10.3). Nullable on the model
/// because curated rows are allowed to omit it when the mechanism does
/// not have a clean directional reading (e.g. binding interactions
/// where neither agent strictly inhibits or enhances the other).
///
/// - `inhibitor` — agent suppresses the other's absorption / efficacy.
/// - `enhancer`  — agent increases the other's bioavailability or effect.
/// - `additive`  — both agents push the same physiologic axis (e.g. two
///                  serotonergic drugs raising serotonin together).
/// - `neutral`   — interaction exists for tracking but neither side
///                  meaningfully modulates the other.
enum EffectType {
  inhibitor,
  enhancer,
  additive,
  neutral;

  /// Lenient parser for the lowercase strings the pipeline writes. Returns
  /// `null` for null/empty/unknown input rather than throwing — the column
  /// is nullable in the schema and unknown values must degrade gracefully
  /// to "no effect type recorded" instead of crashing the lookup path.
  static EffectType? fromString(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final v in EffectType.values) {
      if (v.name == normalized) return v;
    }
    return null;
  }
}

class InteractionResult {
  final String id;
  final InteractionType type;

  /// Severity as DISPLAYED. Food-advisory notes
  /// (`alert_style='food_advisory_note'`) are intentionally rendered
  /// [Severity.informational] here — the app does not track foods in the
  /// user's stack, so the note is surfaced as profile-less context. Keep
  /// using this for the informational display affordance; use
  /// [effectiveSeverity] when weighting the interaction (overall severity,
  /// detail-sheet emphasis) so a genuinely serious advisory
  /// (grapefruit × statin) is not under-weighted.
  final Severity severity;

  /// The REAL curated severity from the interaction row, independent of
  /// the food-advisory informational display downgrade. Preserved so a
  /// serious food advisory keeps its true weight for any consumer that
  /// ranks or scores by severity. `null` only for legacy direct
  /// constructions that predate this field — [effectiveSeverity] falls
  /// back to [severity] in that case.
  final Severity? curatedSeverity;

  final EvidenceLevel evidenceLevel;
  final EffectType? effectType;
  final String agent1Name;
  final String agent2Name;
  final String mechanism;
  final String management;
  final String? alertStyle;
  final String? noteBody;
  final String? practicalGuidance;
  final bool doseDependant;
  final String? doseThreshold;
  final String? direction;
  final String? materiality;
  final String? doseThresholdJson;
  final List<String> sourceUrls;
  final InteractionSource source;

  /// Runtime match context for product-detail warning composition.
  ///
  /// Curated rows preserve their authored agent order, while product-detail
  /// checks normalize display names around the product being viewed. Keeping
  /// the matched supplement id and the actual medication's resolved classes
  /// explicit prevents downstream UI code from guessing which positional
  /// agent is the medication and lets a direct pairwise hit replace the
  /// equivalent generic class warning without collapsing unrelated drugs.
  final String? matchedSupplementCanonicalId;
  final List<String> matchedMedicationClassIds;

  const InteractionResult({
    required this.id,
    required this.type,
    required this.severity,
    required this.evidenceLevel,
    required this.agent1Name,
    required this.agent2Name,
    required this.mechanism,
    required this.management,
    this.alertStyle,
    this.noteBody,
    this.practicalGuidance,
    required this.doseDependant,
    required this.doseThreshold,
    this.direction,
    this.materiality,
    this.doseThresholdJson,
    required this.sourceUrls,
    required this.source,
    this.effectType,
    this.curatedSeverity,
    this.matchedSupplementCanonicalId,
    this.matchedMedicationClassIds = const <String>[],
  });

  /// The severity consumers should WEIGHT by (overall severity, detail
  /// sheet emphasis, ranking). Equals the real curated severity when
  /// present, otherwise the displayed [severity]. For a food advisory
  /// this returns the true severity even though [severity] displays as
  /// informational.
  Severity get effectiveSeverity => curatedSeverity ?? severity;

  /// Hydrate a model from a curated [InteractionRow] read out of the
  /// bundled interaction DB.
  ///
  /// The interaction DB stores agent types as `'drug' | 'drug_class' |
  /// 'supplement'`. We collapse them into the four-value
  /// [InteractionType] enum the rest of the app speaks:
  ///
  ///   - both supplements → [InteractionType.supplementSupplement]
  ///   - both drug-side    → [InteractionType.drugDrug]
  ///   - mixed              → [InteractionType.drugSupplement]
  ///
  /// Drug classes count as "drug-side" for the purposes of this collapse
  /// because every class-as-agent row in the M2 build represents a class
  /// of medications, not a class of supplements.
  ///
  /// `source_urls_json` is decoded best-effort: malformed JSON degrades
  /// to an empty list rather than throwing, because the wrapping lookup
  /// is read-only and one bad row should never break the whole result
  /// page.
  ///
  /// Optional [agent1NameOverride] / [agent2NameOverride] let callers
  /// substitute the user-facing labels they have on hand (e.g. the
  /// supplement product name from the stack), since rows looked up via
  /// drug-class lookups may carry the canonical class name rather than
  /// the brand the user added.
  factory InteractionResult.fromRow(
    InteractionRow row, {
    InteractionSource source = InteractionSource.pipeline,
    String? agent1NameOverride,
    String? agent2NameOverride,
    String? matchedSupplementCanonicalId,
    List<String> matchedMedicationClassIds = const <String>[],
  }) {
    final type1IsDrugSide =
        row.agent1Type == 'drug' || row.agent1Type == 'drug_class';
    final type2IsDrugSide =
        row.agent2Type == 'drug' || row.agent2Type == 'drug_class';

    final InteractionType resolvedType;
    if (!type1IsDrugSide && !type2IsDrugSide) {
      resolvedType = InteractionType.supplementSupplement;
    } else if (type1IsDrugSide && type2IsDrugSide) {
      resolvedType = InteractionType.drugDrug;
    } else {
      resolvedType = InteractionType.drugSupplement;
    }

    final isFoodAdvisory = row.alertStyle == 'food_advisory_note';
    final noteBody = row.noteBody?.trim();
    final practicalGuidance = row.practicalGuidance?.trim();

    return InteractionResult(
      id: row.id,
      type: resolvedType,
      severity: isFoodAdvisory
          ? Severity.informational
          : Severity.fromString(row.severity),
      // Preserve the REAL curated severity regardless of the food-advisory
      // informational display downgrade above, so serious advisories keep
      // their true weight for severity-ranking consumers.
      curatedSeverity: Severity.fromString(row.severity),
      evidenceLevel: row.evidenceLevel == null
          ? EvidenceLevel.ungraded
          : EvidenceLevel.fromString(row.evidenceLevel!),
      effectType: EffectType.fromString(row.effectType),
      agent1Name: agent1NameOverride ?? row.agent1Name,
      agent2Name: agent2NameOverride ?? row.agent2Name,
      mechanism: isFoodAdvisory && noteBody != null && noteBody.isNotEmpty
          ? noteBody
          : row.mechanism,
      management:
          isFoodAdvisory &&
              practicalGuidance != null &&
              practicalGuidance.isNotEmpty
          ? practicalGuidance
          : row.management,
      alertStyle: row.alertStyle,
      noteBody: row.noteBody,
      practicalGuidance: row.practicalGuidance,
      doseDependant: row.doseDependent != 0,
      doseThreshold: row.doseThresholdText,
      direction: row.direction,
      materiality: row.materiality,
      doseThresholdJson: row.doseThresholdJson,
      sourceUrls: _decodeSourceUrls(row.sourceUrlsJson),
      source: source,
      matchedSupplementCanonicalId: matchedSupplementCanonicalId,
      matchedMedicationClassIds: List<String>.unmodifiable(
        matchedMedicationClassIds,
      ),
    );
  }

  bool get isFoodAdvisoryNote => alertStyle == 'food_advisory_note';

  static List<String> _decodeSourceUrls(String json) {
    if (json.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const <String>[];
      return decoded
          .where((e) => e != null)
          .map((e) => e.toString())
          .toList(growable: false);
    } on FormatException {
      return const <String>[];
    }
  }

  /// Returns the midpoint stack penalty for a given severity.
  static int stackPenaltyFor(Severity severity) {
    return switch (severity) {
      Severity.contraindicated => -18,
      Severity.avoid => -12,
      Severity.caution => -7,
      Severity.monitor => -3,
      // Informational tier is profile-less context — no score penalty.
      Severity.informational => 0,
      Severity.safe => 0,
    };
  }
}
