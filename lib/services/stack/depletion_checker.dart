// Depletion Checker — matches user's medications against known
// drug-induced nutrient depletions from medication_depletions.json
// (schema v5.2).
//
// Depletion is chronic (onset months-to-years), not acute. The UI
// tone is deliberately calm — depletion rules surface as "sharing,
// not alarming." When the user's supplement stack already covers a
// depleted nutrient, the card switches to a positive acknowledgement
// ("Nice — you're taking B12, which doctors recommend for long-term
// metformin users.").
//
// See scripts/SAFETY_DATA_PATH_C_PLAN.md in the pipeline repo for
// the authored-copy contract and scripts/safety_copy_exemplars/
// depletion_drafts.json for exemplars.

/// How well the user's supplement stack covers a detected depletion.
///
/// - [none] — nutrient is not in the user's stack at all.
/// - [partial] — nutrient is present but below the pipeline's
///   `adequacy_threshold_mcg` / `adequacy_threshold_mg`. The UI nudges
///   the user toward a higher-dose option without alarm.
/// - [adequate] — nutrient is present at or above the threshold (or
///   the pipeline didn't author a threshold, in which case presence
///   alone counts as adequate).
enum CoverageLevel {
  none,
  partial,
  adequate;

  bool get isCovered => this == CoverageLevel.adequate;
  bool get isAnyCoverage =>
      this == CoverageLevel.adequate || this == CoverageLevel.partial;
}

/// A matched depletion between a user's medication and a nutrient.
class DepletionMatch {
  final String depletionId;
  final String drugDisplayName;
  final String drugClassId;
  final String nutrientName;
  final String nutrientCanonicalId;
  final String severity;

  /// Clinical mechanism — surfaced only in an expandable "Why does this
  /// happen?" section, not in the default view.
  final String mechanism;

  /// Pipeline v5.0 recommendation field — clinician-voiced. Kept for
  /// expandable detail; not rendered as the primary body copy.
  final String recommendation;

  final List<String> sourceUrls;

  /// Pipeline v5.0 `onset_timeline` (e.g., "years", "months"). Null on
  /// older data. Used by the UI to set calming expectations.
  final String? onsetTimeline;

  /// Pipeline v5.0 `clinical_impact` — symptom-forward layperson-
  /// relevant copy (e.g., "30% of long-term users develop B12
  /// deficiency"). Null until surfaced per-entry.
  final String? clinicalImpact;

  /// Pipeline v5.2.1 `food_sources_short` — optional inclusive-framing
  /// copy naming dietary sources of the depleted nutrient. For
  /// absorption-blocked depletions (metformin+B12, PPI+B12, statin+
  /// CoQ10) Dr. Pham authors the honest hint pattern: "Because X
  /// reduces Y absorption, food sources may not be enough on their
  /// own — a supplement is often more reliable." Null on entries Dr.
  /// Pham intentionally skipped.
  final String? foodSourcesShort;

  // --- Schema v5.2 authored layperson copy (all optional during
  // authoring transition; Flutter falls back to legacy fields). ---

  /// Authored headline shown as the item title. Falls back to a
  /// "nutrient from medication"-style string if null.
  final String? alertHeadline;

  /// Authored body copy shown when coverage is none/partial. Includes
  /// onset framing so chronic risk is understood as chronic. Falls back
  /// to [clinicalImpact] → [recommendation] when null.
  final String? alertBody;

  /// Authored validation copy shown when coverage is adequate. "Nice —
  /// you're already taking this" framing. Zero caution verbs per
  /// validator contract.
  final String? acknowledgementNote;

  /// Authored soft-action tip shown in all states. Always uses calm
  /// action verbs (check, consider, monitor).
  final String? monitoringTipShort;

  /// Schema v5.2 adequacy threshold (if authored). Used by the checker
  /// to decide whether stack coverage is [CoverageLevel.adequate] vs
  /// [CoverageLevel.partial].
  final num? adequacyThresholdMcg;
  final num? adequacyThresholdMg;

  /// Three-state coverage outcome for this user's stack. See
  /// [CoverageLevel].
  final CoverageLevel coverageLevel;

  /// True if the user already has a supplement in their stack that
  /// covers this depleted nutrient. Equivalent to
  /// `coverageLevel.isCovered`; retained as a convenience alias so
  /// existing call sites compile.
  bool get isCovered => coverageLevel.isCovered;

  const DepletionMatch({
    required this.depletionId,
    required this.drugDisplayName,
    required this.drugClassId,
    required this.nutrientName,
    required this.nutrientCanonicalId,
    required this.severity,
    required this.mechanism,
    required this.recommendation,
    this.sourceUrls = const [],
    this.onsetTimeline,
    this.clinicalImpact,
    this.alertHeadline,
    this.alertBody,
    this.acknowledgementNote,
    this.monitoringTipShort,
    this.foodSourcesShort,
    this.adequacyThresholdMcg,
    this.adequacyThresholdMg,
    this.coverageLevel = CoverageLevel.none,
  });
}

/// Minimal supplement-in-stack description used for dose-aware coverage
/// computation. One entry per (supplement, ingredient) pair the user
/// is currently taking.
class StackSupplementDose {
  /// Canonical id of the ingredient (e.g., "vitamin_b12"). Matched
  /// case-insensitively against the depletion entry's
  /// `depleted_nutrient.canonical_id`.
  final String canonicalId;

  /// Dose per serving in native units. Null if the pipeline didn't
  /// normalize a dose for this ingredient.
  final num? doseAmount;
  final String? doseUnit;

  const StackSupplementDose({
    required this.canonicalId,
    this.doseAmount,
    this.doseUnit,
  });
}

class DepletionChecker {
  /// Check user's medications against known depletions.
  ///
  /// [medications] — user's stack entries of type 'medication'.
  /// [depletionsData] — parsed `medication_depletions.json` (v5.2 shape).
  /// [stackCanonicalIds] — set of canonical IDs from supplement stack,
  ///   used as the baseline coverage signal. Supply this when you only
  ///   have presence/absence data (no doses); results will be
  ///   [CoverageLevel.adequate] or [CoverageLevel.none] — never
  ///   [CoverageLevel.partial].
  /// [stackDoses] — optional dose-aware coverage data. When supplied,
  ///   doses are compared to the depletion's `adequacy_threshold_mcg` /
  ///   `adequacy_threshold_mg` to emit [CoverageLevel.partial] for
  ///   below-threshold coverage.
  List<DepletionMatch> check({
    required List<({String name, String? drugClassId})> medications,
    required Map<String, dynamic> depletionsData,
    Set<String> stackCanonicalIds = const {},
    List<StackSupplementDose> stackDoses = const [],
  }) {
    final depletions = depletionsData['depletions'] as List? ?? [];
    final results = <DepletionMatch>[];

    // Build a set of user's drug class IDs for matching.
    final userDrugClassIds = <String>{};
    final userDrugNames = <String>{};
    for (final med in medications) {
      if (med.drugClassId != null && med.drugClassId!.isNotEmpty) {
        userDrugClassIds.add(med.drugClassId!.toLowerCase());
      }
      userDrugNames.add(med.name.toLowerCase());
    }

    // Index stack doses by canonical id (lowercased).
    final dosesByCid = <String, StackSupplementDose>{};
    for (final d in stackDoses) {
      dosesByCid[d.canonicalId.toLowerCase()] = d;
    }
    final coveredIdsLower = stackCanonicalIds
        .map((e) => e.toLowerCase())
        .toSet();

    for (final dep in depletions) {
      if (dep is! Map<String, dynamic>) continue;

      final drugRef = dep['drug_ref'] as Map<String, dynamic>? ?? {};
      final drugId = (drugRef['id']?.toString() ?? '').toLowerCase();
      final drugDisplayName = drugRef['display_name']?.toString() ?? '';

      // Match by drug class ID or drug name substring
      final matches =
          userDrugClassIds.any((id) => drugId.contains(id)) ||
          userDrugNames.any(
            (name) =>
                drugDisplayName.toLowerCase().contains(name) ||
                name.contains(drugDisplayName.toLowerCase()),
          );

      if (!matches) continue;

      final nutrient = dep['depleted_nutrient'] as Map<String, dynamic>? ?? {};
      final canonicalId = (nutrient['canonical_id']?.toString() ?? '')
          .toLowerCase();

      final sourceUrls =
          (dep['sources'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((s) => s['url']?.toString() ?? '')
              .where((u) => u.isNotEmpty)
              .toList() ??
          const [];

      final adequacyMcg = _asNum(dep['adequacy_threshold_mcg']);
      final adequacyMg = _asNum(dep['adequacy_threshold_mg']);

      final coverage = _resolveCoverage(
        canonicalId: canonicalId,
        coveredIds: coveredIdsLower,
        dose: dosesByCid[canonicalId],
        thresholdMcg: adequacyMcg,
        thresholdMg: adequacyMg,
      );

      results.add(
        DepletionMatch(
          depletionId: dep['id']?.toString() ?? '',
          drugDisplayName: drugDisplayName,
          drugClassId: drugId,
          nutrientName: nutrient['standard_name']?.toString() ?? '',
          nutrientCanonicalId: canonicalId,
          severity: dep['severity']?.toString() ?? 'moderate',
          mechanism: dep['mechanism']?.toString() ?? '',
          recommendation: dep['recommendation']?.toString() ?? '',
          sourceUrls: sourceUrls,
          onsetTimeline: dep['onset_timeline']?.toString(),
          clinicalImpact: dep['clinical_impact']?.toString(),
          alertHeadline: dep['alert_headline']?.toString(),
          alertBody: dep['alert_body']?.toString(),
          acknowledgementNote: dep['acknowledgement_note']?.toString(),
          monitoringTipShort: dep['monitoring_tip_short']?.toString(),
          foodSourcesShort: dep['food_sources_short']?.toString(),
          adequacyThresholdMcg: adequacyMcg,
          adequacyThresholdMg: adequacyMg,
          coverageLevel: coverage,
        ),
      );
    }

    // Sort: uncovered first, then partial, then covered.
    // Within each tier, sort by severity desc.
    results.sort((a, b) {
      final aw = _coverageSortWeight(a.coverageLevel);
      final bw = _coverageSortWeight(b.coverageLevel);
      if (aw != bw) return aw.compareTo(bw);
      return _severityWeight(b.severity).compareTo(_severityWeight(a.severity));
    });

    return results;
  }

  /// Decide the three-state coverage level for a single depletion.
  static CoverageLevel _resolveCoverage({
    required String canonicalId,
    required Set<String> coveredIds,
    required StackSupplementDose? dose,
    required num? thresholdMcg,
    required num? thresholdMg,
  }) {
    final hasPresence = coveredIds.contains(canonicalId) || dose != null;
    if (!hasPresence) return CoverageLevel.none;

    // If no threshold authored, presence == adequate (v5.2 default when
    // dose-sensitivity isn't authored).
    if (thresholdMcg == null && thresholdMg == null) {
      return CoverageLevel.adequate;
    }

    // Threshold authored but we don't have a dose — assume presence
    // alone is at least partial coverage. The UI phrases this as "you're
    // taking some X" rather than "you're adequately covered."
    if (dose == null || dose.doseAmount == null || dose.doseUnit == null) {
      return CoverageLevel.partial;
    }

    final normalizedMcg = _toMcg(dose.doseAmount!, dose.doseUnit!);
    if (normalizedMcg == null) {
      // Unit we don't know how to convert (rare) — treat as partial.
      return CoverageLevel.partial;
    }

    final thresholdInMcg = thresholdMcg ?? (thresholdMg! * 1000);
    if (normalizedMcg >= thresholdInMcg) {
      return CoverageLevel.adequate;
    }
    return CoverageLevel.partial;
  }

  /// Convert a (amount, unit) pair to micrograms for adequacy
  /// comparison. Returns null for unrecognized units; the caller treats
  /// that as a partial-coverage signal.
  static double? _toMcg(num amount, String unit) {
    final u = unit.trim().toLowerCase();
    final a = amount.toDouble();
    // mcg / μg / ug synonyms.
    if (u == 'mcg' || u == 'μg' || u == 'ug') return a;
    if (u == 'mg') return a * 1000.0;
    if (u == 'g') return a * 1000000.0;
    // IU conversion is nutrient-specific (vitamin A/D/E each have
    // different factors). We intentionally don't convert here — the
    // pipeline normalizes to mass units before emission for most
    // supplements. Return null so the caller treats IU doses as partial.
    return null;
  }

  static int _coverageSortWeight(CoverageLevel c) {
    switch (c) {
      case CoverageLevel.none:
        return 0;
      case CoverageLevel.partial:
        return 1;
      case CoverageLevel.adequate:
        return 2;
    }
  }

  static int _severityWeight(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return 4;
      case 'significant':
        return 3;
      case 'moderate':
        return 2;
      case 'mild':
        return 1;
      default:
        return 0;
    }
  }

  static num? _asNum(Object? v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }
}
