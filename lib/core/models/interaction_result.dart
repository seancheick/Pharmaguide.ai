import 'dart:convert';

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';

enum InteractionType {
  drugSupplement,
  supplementSupplement,
  drugDrug,
  conditionSupplement,
}

enum InteractionSource {
  pipeline,
  stackEngine,
  aiChat,
}

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
  final Severity severity;
  final EvidenceLevel evidenceLevel;
  final EffectType? effectType;
  final String agent1Name;
  final String agent2Name;
  final String mechanism;
  final String management;
  final bool doseDependant;
  final String? doseThreshold;
  final List<String> sourceUrls;
  final InteractionSource source;

  const InteractionResult({
    required this.id,
    required this.type,
    required this.severity,
    required this.evidenceLevel,
    required this.agent1Name,
    required this.agent2Name,
    required this.mechanism,
    required this.management,
    required this.doseDependant,
    required this.doseThreshold,
    required this.sourceUrls,
    required this.source,
    this.effectType,
  });

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

    return InteractionResult(
      id: row.id,
      type: resolvedType,
      severity: Severity.fromString(row.severity),
      evidenceLevel: row.evidenceLevel == null
          ? EvidenceLevel.theoretical
          : EvidenceLevel.fromString(row.evidenceLevel!),
      effectType: EffectType.fromString(row.effectType),
      agent1Name: agent1NameOverride ?? row.agent1Name,
      agent2Name: agent2NameOverride ?? row.agent2Name,
      mechanism: row.mechanism,
      management: row.management,
      doseDependant: row.doseDependent != 0,
      doseThreshold: row.doseThresholdText,
      sourceUrls: _decodeSourceUrls(row.sourceUrlsJson),
      source: source,
    );
  }

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
