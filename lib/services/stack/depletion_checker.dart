// Depletion Checker — matches user's medications against medication-
// nutrient notes from medication_depletions.json
// (schema v5.3).
//
// Most rows are chronic depletions (onset months-to-years), but schema
// v5.3 also distinguishes functional antagonism, monitoring/stability,
// condition-related nutrient issues, and supplement interactions. The UI
// tone is deliberately calm — rules surface as "sharing, not alarming."
// When the user's supplement stack already covers a true depleted nutrient,
// the card switches to positive acknowledgement copy.
//
// See scripts/SAFETY_DATA_PATH_C_PLAN.md in the pipeline repo for
// the authored-copy contract and scripts/safety_copy_exemplars/
// depletion_drafts.json for exemplars.

import 'package:pharmaguide/core/units/dose_units.dart';

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

/// One cited source from the reviewed medication–nutrient artifact. Keeping
/// the authored label and type prevents the UI from degrading every citation
/// into an indistinguishable "Source" link.
class DepletionSource {
  final String sourceType;
  final String label;
  final String url;

  const DepletionSource({
    required this.sourceType,
    required this.label,
    required this.url,
  });
}

/// A matched medication-nutrient note for a user's medication.
class DepletionMatch {
  final String depletionId;
  final String drugDisplayName;
  final String drugClassId;
  final String nutrientName;
  final String nutrientCanonicalId;

  /// Schema v5.3 taxonomy. True drug-induced nutrient depletion is only one
  /// bucket; rows can also describe functional antagonism, monitoring/stability
  /// notes, condition-related nutrient issues, or supplement interactions.
  final String depletionType;

  final String severity;

  /// Evidence grade authored by the pipeline for this relationship.
  /// Defaults conservatively for legacy assets.
  final String evidenceLevel;

  /// Clinical mechanism — surfaced only in an expandable "Why does this
  /// happen?" section, not in the default view.
  final String mechanism;

  /// Pipeline v5.0 recommendation field — clinician-voiced. Kept for
  /// expandable detail; not rendered as the primary body copy.
  final String recommendation;

  final List<DepletionSource> sources;
  final List<String> _legacySourceUrls;

  /// URL-only compatibility view for older callers and report exporters.
  List<String> get sourceUrls => sources.isNotEmpty
      ? sources.map((source) => source.url).toList(growable: false)
      : _legacySourceUrls;

  /// Pipeline v5.0 `onset_timeline` (e.g., "years", "months"). Null on
  /// older data. Used by the UI to set calming expectations.
  final String? onsetTimeline;

  /// Optional curated watch threshold, in days of continuous tracking, after
  /// which this relationship becomes worth revisiting. Authored per entry by a
  /// clinical reviewer alongside [watchBasis]; the app never derives or
  /// defaults it. `onsetTimeline` is a coarse bucket for copy framing and
  /// cannot answer "is this due yet?", which is why this exists separately.
  ///
  /// Null on every entry a reviewer has not authored — those entries are simply
  /// not watched, so the feature degrades to prior behavior rather than
  /// inventing a clinical timeline.
  final int? watchThresholdDays;

  /// The reviewer's cited justification for [watchThresholdDays], drawn from
  /// the same source set already on the entry. Present whenever a threshold is,
  /// so a threshold can never appear without its provenance.
  final String? watchBasis;

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

  /// Detected total stack supply of this nutrient (summed across the stack),
  /// null when no dose data is available. Drives the factual "your stack
  /// contains X {unit} per day" supply copy (B1.1).
  final num? detectedAmount;
  final String? detectedUnit;

  /// Citation-review status from the versioned artifact (B1.2): unverified /
  /// verified / needs_revision / rejected. Only verified records may surface;
  /// every other value fails closed. Defaults to 'unverified' for a pre-B1.2
  /// asset, which therefore remains suppressed.
  final String citationReviewStatus;

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
    this.depletionType = 'depletion',
    required this.severity,
    this.evidenceLevel = 'ungraded',
    required this.mechanism,
    required this.recommendation,
    this.sources = const [],
    List<String> sourceUrls = const [],
    this.onsetTimeline,
    this.watchThresholdDays,
    this.watchBasis,
    this.clinicalImpact,
    this.alertHeadline,
    this.alertBody,
    this.acknowledgementNote,
    this.monitoringTipShort,
    this.foodSourcesShort,
    this.adequacyThresholdMcg,
    this.adequacyThresholdMg,
    this.detectedAmount,
    this.detectedUnit,
    this.citationReviewStatus = 'unverified',
    this.coverageLevel = CoverageLevel.none,
  }) : _legacySourceUrls = sourceUrls;
}

/// Consumer-facing label for a medication–nutrient relationship. Keeps each
/// [DepletionMatch.depletionType] honest: a functional antagonism or a
/// monitoring note is never presented as a "depletion" (PM-locked, B1.1).
/// Unknown/future types fall back to a neutral label, never "depletion".
String medNutrientRelationshipLabel(String depletionType) {
  switch (depletionType.trim().toLowerCase()) {
    case 'depletion':
      return 'Medication/nutrient guidance';
    case 'condition_related':
      return 'Condition/nutrient guidance';
    case 'functional_antagonism':
      return 'Medication/nutrient guidance';
    case 'monitoring_stability':
      return 'Medication/nutrient guidance';
    case 'supplement_interaction':
      return 'Supplement interaction';
    default:
      return 'Nutrient consideration';
  }
}

/// Consumer-facing supply state for a medication–nutrient row. Deliberately
/// distinct from the internal [CoverageLevel] — the card renders these, never
/// none/partial/adequate (PM-locked, B1.1).
enum MedNutrientSupplyState {
  noDetectedSource,
  sourceDetectedBelowComparison,
  meetsComparisonAmount,
  sourceAmountUnknown,
}

/// Translate the internal coverage band + amount availability into the
/// consumer supply state. An "adequate" band with no known amount is
/// [sourceAmountUnknown] (present but unquantified), never a sufficiency claim.
MedNutrientSupplyState medNutrientSupplyStateFrom(
  CoverageLevel coverage, {
  required bool hasAmount,
}) {
  switch (coverage) {
    case CoverageLevel.none:
      return MedNutrientSupplyState.noDetectedSource;
    case CoverageLevel.partial:
      return MedNutrientSupplyState.sourceDetectedBelowComparison;
    case CoverageLevel.adequate:
      return hasAmount
          ? MedNutrientSupplyState.meetsComparisonAmount
          : MedNutrientSupplyState.sourceAmountUnknown;
  }
}

String _fmtAmt(num n) => n == n.roundToDouble() ? n.round().toString() : '$n';

/// Factual body copy for one medication–nutrient row, selected from an explicit
/// relationship_type × supply_state template — never one interpolated universal
/// sentence (PM-locked, B1.1). Stays factual: no "covered"/"adequate"/
/// replacement claims. Amounts carry a per-day basis and never imply a measured
/// deficiency or physiological sufficiency. Clinician-reviewed context is
/// preferred when supplied; [subject] is the drug or condition.
String medNutrientBodyCopy({
  required String relationshipType,
  required String nutrient,
  required String subject,
  MedNutrientSupplyState? supplyState,
  num? detectedAmount,
  String? detectedUnit,
  String? reviewedContext,
  num? comparisonAmount,
  String? comparisonUnit,
}) {
  final type = relationshipType.trim().toLowerCase();
  final n = nutrient.trim().isEmpty ? 'this nutrient' : nutrient.trim();
  final subj = subject.trim().isEmpty ? 'your medication' : subject.trim();

  final amountPhrase =
      (detectedAmount != null && (detectedUnit ?? '').isNotEmpty)
      ? '${_fmtAmt(detectedAmount)} ${detectedUnit!.trim()}'
      : '';
  final reviewed = reviewedContext?.trim() ?? '';

  switch (type) {
    case 'functional_antagonism':
      if (reviewed.isNotEmpty) return reviewed;
      return '$subj may affect how the body uses $n. This does not confirm '
          'that your $n level is low. Ask your clinician whether monitoring '
          'is appropriate for you.';
    case 'monitoring_stability':
      if (reviewed.isNotEmpty) return reviewed;
      return 'Monitoring $n may be relevant while taking $subj. Ask your '
          'clinician whether testing or follow-up is appropriate.';
    case 'supplement_interaction':
      if (reviewed.isNotEmpty) return reviewed;
      return '$n may interact with $subj. Review the interaction details and '
          'discuss timing or use with your clinician or pharmacist.';
    case 'condition_related':
      final lead = '$n may be relevant to monitor with $subj.';
      final supply = switch (supplyState) {
        MedNutrientSupplyState.noDetectedSource =>
          'No $n source was detected in your current stack.',
        MedNutrientSupplyState.sourceAmountUnknown =>
          'Your current stack includes a source of $n, but the daily amount '
              'could not be determined.',
        _ when amountPhrase.isNotEmpty =>
          'Your current stack contains $amountPhrase of $n per day.',
        _ => 'Your current stack includes a source of $n.',
      };
      final context = reviewed.isEmpty ? lead : reviewed;
      return '$supply $context Supplement intake does not confirm your blood '
          'level or nutrient status.';
    case 'depletion':
    default:
      // Unknown/future types get a safe informational line, never "depletion".
      if (type != 'depletion') {
        return '$n may be relevant to review alongside $subj. Supplement '
            'intake does not confirm your $n status.';
      }
      // A below/meets state with no known amount degrades to amount-unknown
      // so we never render "contains  of X per day".
      var state = supplyState ?? MedNutrientSupplyState.sourceAmountUnknown;
      if ((state == MedNutrientSupplyState.sourceDetectedBelowComparison ||
              state == MedNutrientSupplyState.meetsComparisonAmount) &&
          amountPhrase.isEmpty) {
        state = MedNutrientSupplyState.sourceAmountUnknown;
      }
      switch (state) {
        case MedNutrientSupplyState.noDetectedSource:
          final context = reviewed.isEmpty
              ? '$subj use has been associated with lower $n status in some '
                    'people. Consider asking your clinician whether monitoring '
                    'is appropriate.'
              : reviewed;
          return 'No $n source detected in your current stack. $context';
        case MedNutrientSupplyState.sourceDetectedBelowComparison:
        case MedNutrientSupplyState.meetsComparisonAmount:
          final context = reviewed.isEmpty ? '' : ' $reviewed';
          return 'Your stack provides $amountPhrase/day of $n.$context '
              'Supplement intake does not confirm your blood level or '
              'nutrient status.';
        case MedNutrientSupplyState.sourceAmountUnknown:
          final context = reviewed.isEmpty ? '' : ' $reviewed';
          return 'Your stack includes $n, but the daily amount could not be '
              'determined.$context Supplement intake does not confirm your '
              'blood level or nutrient status.';
      }
  }
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

/// Medication identity used by the depletion checker.
///
/// Depletion rows can be keyed to a generic drug RxCUI, while the user may
/// add a brand or combination medication. Keep every resolved RxNorm identity
/// in play so brand picks like Xenical can still match generic rows authored
/// against orlistat.
class DepletionMedicationIdentity {
  final String name;
  final String? rxcui;
  final String? genericRxcui;
  final List<String> ingredientRxcuis;
  final List<String> drugClassIds;

  const DepletionMedicationIdentity({
    required this.name,
    this.rxcui,
    this.genericRxcui,
    this.ingredientRxcuis = const [],
    this.drugClassIds = const [],
  });
}

/// The medication-nutrient artifact runtime contract this app build supports.
/// The app can render a versioned artifact whose minimum_runtime_contract is
/// <= this value (B1.2). Bump when the app learns to render a newer shape.
const int kMedNutrientRuntimeContract = 1;

/// Join-key aliases between the catalog ingredient namespace and the reviewed
/// medication-depletion nutrient namespace.
///
/// The pipeline intentionally keeps form-family IDs such as
/// `vitamin_b12_cobalamin`, while the clinical artifact uses the nutrient
/// group `vitamin_b12`. Normalizing only at this boundary preserves both
/// source artifacts and prevents a supplement that contains the nutrient from
/// being reported as "no source detected".
const Map<String, String> _depletionCoverageCanonicalAliases = {
  'vitamin_b1_thiamine': 'thiamin',
  'vitamin_b6_pyridoxine': 'vitamin_b6',
  'vitamin_b7_biotin': 'biotin',
  'vitamin_b9_folate': 'folate',
  'vitamin_b12_cobalamin': 'vitamin_b12',
  'vitamin_d2': 'vitamin_d',
  'vitamin_d3': 'vitamin_d',
  'vitamin_k1': 'vitamin_k',
  'vitamin_k2': 'vitamin_k',
};

String _depletionCoverageCanonicalId(String raw) {
  final canonical = raw.trim().toLowerCase();
  return _depletionCoverageCanonicalAliases[canonical] ?? canonical;
}

/// Activation-compatibility verdict for a loaded medication-depletions artifact
/// (B1.2 App-1). A legacy asset with no _metadata is allowed (migration — never
/// blank the monitor); a versioned asset is rejected only when it declares a
/// newer runtime contract than this build supports, or is structurally corrupt.
({bool compatible, bool isLegacy, String reason})
checkMedicationDepletionsArtifact(Map<String, dynamic> data) {
  final depletions = data['depletions'];
  if (depletions is! List) {
    return (
      compatible: false,
      isLegacy: false,
      reason: 'missing depletions list',
    );
  }
  final meta = data['_metadata'];
  if (meta is! Map) {
    // Pre-B1.2 asset: no versioning. Allowed so the migration keeps working.
    return (compatible: true, isLegacy: true, reason: 'legacy (no _metadata)');
  }
  final minRuntime = meta['minimum_runtime_contract'];
  if (minRuntime is! int) {
    return (
      compatible: false,
      isLegacy: false,
      reason: 'missing/invalid minimum_runtime_contract',
    );
  }
  if (minRuntime > kMedNutrientRuntimeContract) {
    return (
      compatible: false,
      isLegacy: false,
      reason:
          'artifact requires runtime contract $minRuntime > '
          'supported $kMedNutrientRuntimeContract',
    );
  }
  return (compatible: true, isLegacy: false, reason: 'ok');
}

/// Outcome of loading + activating the medication-depletions artifact (B1.2).
/// [unavailable] must NOT be rendered as a clean "no depletions" state — a
/// failed activation is not an all-clear. [fallbackLoaded] is reserved for when
/// a last-known-good artifact is used (no OTA/last-good support yet, so the
/// bundled artifact is currently the only source).
enum MedNutrientLoadStatus { loaded, fallbackLoaded, unavailable }

/// The medication-nutrient report: an activation [status] plus the matched
/// depletions. Consumers MUST branch on [status] — an [unavailable] status with
/// empty [matches] is NOT the same as a [loaded] status with empty matches (the
/// former shows a "check unavailable" state, never a false all-clear).
typedef MedNutrientReport = ({
  MedNutrientLoadStatus status,
  List<DepletionMatch> matches,
});

/// Apply the App-1 activation gate to a loaded artifact. Returns [loaded] with
/// the artifact when compatible; otherwise [unavailable] with a safe empty
/// payload (no depletions) and invokes [onIncompatible] with the reason. The
/// caller MUST surface [unavailable] as an explicit "check unavailable" state,
/// never a false clean state (a failed activation is not an all-clear).
({MedNutrientLoadStatus status, Map<String, dynamic> data})
activateMedicationDepletionsArtifact(
  Map<String, dynamic> data, {
  void Function(String reason)? onIncompatible,
}) {
  final check = checkMedicationDepletionsArtifact(data);
  if (check.compatible) {
    return (status: MedNutrientLoadStatus.loaded, data: data);
  }
  onIncompatible?.call(check.reason);
  return (
    status: MedNutrientLoadStatus.unavailable,
    data: <String, dynamic>{
      if (data['_metadata'] is Map) '_metadata': data['_metadata'],
      'depletions': const <dynamic>[],
    },
  );
}

/// Consumer-facing publication eligibility for a medication–nutrient entry,
/// derived from its `citation_review_status` (B1.2). This is the ONE place the
/// policy lives — the checker gates display on it, and A2 must consume these
/// fields rather than reinterpret the raw status. `notificationAllowed` is the
/// review-status permission only; the signal's disposition decides separately.
typedef MedNutrientPublication = ({
  bool displayAllowed,
  bool persistenceAllowed,
  bool notificationAllowed,
});

/// Map a `citation_review_status` to its publication eligibility (B1.2).
/// Only verified records may display, persist, or notify. Every other value,
/// including unknown future statuses, fails closed.
MedNutrientPublication medNutrientPublicationPolicy(
  String citationReviewStatus,
) {
  switch (citationReviewStatus.trim().toLowerCase()) {
    case 'verified':
      return (
        displayAllowed: true,
        persistenceAllowed: true,
        notificationAllowed: true,
      );
    case 'needs_revision':
    case 'rejected':
      return (
        displayAllowed: false,
        persistenceAllowed: false,
        notificationAllowed: false,
      );
    case 'unverified':
    default:
      return (
        displayAllowed: false,
        persistenceAllowed: false,
        notificationAllowed: false,
      );
  }
}

class DepletionChecker {
  /// Check user's medications against known medication-nutrient notes.
  ///
  /// [medications] — user's stack entries of type 'medication'.
  /// [depletionsData] — parsed `medication_depletions.json` (v5.3 shape).
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
    List<DepletionMedicationIdentity> medicationIdentities = const [],
    required Map<String, dynamic> depletionsData,
    Set<String> stackCanonicalIds = const {},
    List<StackSupplementDose> stackDoses = const [],
    void Function(String message)? onDataIssue,
  }) {
    final depletions = depletionsData['depletions'] as List? ?? [];
    final results = <DepletionMatch>[];

    // Build medication identity sets for matching. Keep the legacy
    // `(name, drugClassId)` record input as a compatibility layer, but prefer
    // [DepletionMedicationIdentity] for real app wiring because it carries
    // brand/generic/ingredient RxCUIs.
    final identities = <DepletionMedicationIdentity>[
      for (final med in medications)
        DepletionMedicationIdentity(
          name: med.name,
          drugClassIds: [
            if (med.drugClassId != null && med.drugClassId!.isNotEmpty)
              med.drugClassId!,
          ],
        ),
      ...medicationIdentities,
    ];

    final userDrugClassIds = <String>{};
    final userDrugNames = <String>{};
    final userDrugRxcuis = <String>{};
    for (final med in identities) {
      for (final id in med.drugClassIds) {
        final normalized = id.trim().toLowerCase();
        if (normalized.isNotEmpty) userDrugClassIds.add(normalized);
      }
      for (final id in [med.rxcui, med.genericRxcui, ...med.ingredientRxcuis]) {
        final normalized = id?.trim();
        if (normalized != null && normalized.isNotEmpty) {
          userDrugRxcuis.add(normalized);
          userDrugRxcuis.add(normalized.toLowerCase());
        }
      }
      // Name matching is a legacy fallback for entries that carry NO
      // structured RxCUI at all. Identity-backed meds match by RxCUI;
      // including their names too caused substring false positives.
      final hasRxcui = [
        med.rxcui,
        med.genericRxcui,
        ...med.ingredientRxcuis,
      ].any((id) => id != null && id.trim().isNotEmpty);
      if (!hasRxcui) {
        userDrugNames.add(med.name.toLowerCase());
      }
    }

    // Index stack doses by canonical id (lowercased).
    final dosesByCid = <String, StackSupplementDose>{};
    for (final d in stackDoses) {
      dosesByCid[_depletionCoverageCanonicalId(d.canonicalId)] = d;
    }
    final coveredIdsLower = stackCanonicalIds
        .map(_depletionCoverageCanonicalId)
        .toSet();

    // Identity integrity (B1.1): every entry's stable `id` must be present and
    // unique. A missing id (previously silently emitted as '') or a duplicate id
    // makes the derived signal identity unstable/colliding, so the entry is
    // dropped. The pipeline is the primary asset gate; this is the app's
    // defensive skip so no signal is ever emitted without a stable identity.
    final idCounts = <String, int>{};
    var missingIdCount = 0;
    for (final dep in depletions) {
      if (dep is! Map<String, dynamic>) continue;
      final id = dep['id']?.toString().trim() ?? '';
      if (id.isEmpty) {
        missingIdCount++;
      } else {
        idCounts[id] = (idCounts[id] ?? 0) + 1;
      }
    }
    final duplicateIds = <String>{
      for (final e in idCounts.entries)
        if (e.value > 1) e.key,
    };
    if (missingIdCount > 0) {
      onDataIssue?.call(
        'medication_depletions: dropped $missingIdCount '
        '${missingIdCount == 1 ? 'entry' : 'entries'} with a missing id',
      );
    }
    if (duplicateIds.isNotEmpty) {
      onDataIssue?.call(
        'medication_depletions: dropped duplicate ids — '
        '${(duplicateIds.toList()..sort()).join(', ')}',
      );
    }

    for (final dep in depletions) {
      if (dep is! Map<String, dynamic>) continue;
      final depId = dep['id']?.toString().trim() ?? '';
      if (depId.isEmpty || duplicateIds.contains(depId)) continue;

      final drugRef = dep['drug_ref'] as Map<String, dynamic>? ?? {};
      final drugIdRaw = drugRef['id']?.toString().trim() ?? '';
      final drugId = drugIdRaw.toLowerCase();
      final drugRefType = (drugRef['type']?.toString() ?? '').toLowerCase();
      final drugDisplayName = drugRef['display_name']?.toString() ?? '';

      final isDrugRef =
          drugRefType == 'drug' || RegExp(r'^\d+$').hasMatch(drugIdRaw);
      final isClassRef = drugRefType == 'class' || drugId.startsWith('class:');

      // Match by RxCUI or drug class ID. The legacy display-name
      // fallback covers user meds with no structured RxCUI; raw
      // bidirectional substring matching produced false positives
      // (e.g. "iron" inside unrelated names), so it now requires a
      // word-boundary match of at least 5 characters.
      final matches =
          (isDrugRef && userDrugRxcuis.contains(drugIdRaw)) ||
          (isDrugRef && userDrugRxcuis.contains(drugId)) ||
          (isClassRef &&
              userDrugClassIds.any(
                (id) => drugId == id || drugId.contains(id),
              )) ||
          userDrugNames.any(
            (name) =>
                legacyDrugNameMatches(drugDisplayName.toLowerCase(), name),
          );

      if (!matches) continue;

      // Citation-review publication rule (B1.2): only verified records surface.
      // Missing, unverified, rejected, needs_revision, and unknown future
      // statuses all fail closed.
      var reviewStatus =
          (dep['citation_review_status']?.toString() ?? 'unverified')
              .trim()
              .toLowerCase();
      if (!medNutrientPublicationPolicy(reviewStatus).displayAllowed) {
        onDataIssue?.call(
          'medication_depletions: suppressed $depId '
          '(citation_review_status=$reviewStatus, display not allowed)',
        );
        continue;
      }
      if (reviewStatus != 'verified' && reviewStatus != 'unverified') {
        reviewStatus = 'unverified';
      }

      final nutrient = dep['depleted_nutrient'] as Map<String, dynamic>? ?? {};
      final canonicalId = (nutrient['canonical_id']?.toString() ?? '')
          .trim()
          .toLowerCase();
      final coverageCanonicalId = _depletionCoverageCanonicalId(canonicalId);

      // Canonical-subject validation (B1.1, app-defensive): the signal subjects
      // are the drug/condition + the nutrient canonical id. Missing either makes
      // the signal identity unstable, so drop it. The pipeline is the primary
      // gate that resolves these ids against the catalog and rejects a malformed
      // asset outright.
      final hasDrugSubject =
          drugId.trim().isNotEmpty || drugDisplayName.trim().isNotEmpty;
      if (canonicalId.isEmpty || !hasDrugSubject) {
        onDataIssue?.call(
          'medication_depletions: dropped $depId — missing canonical subject '
          '(nutrient="$canonicalId", drug="$drugId"/"$drugDisplayName")',
        );
        continue;
      }

      final sources =
          (dep['sources'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(_parseSource)
              .whereType<DepletionSource>()
              .toList() ??
          const [];

      final adequacyMcg = _asNum(dep['adequacy_threshold_mcg']);
      final adequacyMg = _asNum(dep['adequacy_threshold_mg']);
      final depletionType = _normalizeDepletionType(dep['depletion_type']);
      final (:watchThresholdDays, :watchBasis) = _parseWatchThreshold(dep);

      final matchedDose = dosesByCid[coverageCanonicalId];
      final coverage = _isSupplementCoverageRelevant(depletionType)
          ? _resolveCoverage(
              canonicalId: coverageCanonicalId,
              coveredIds: coveredIdsLower,
              dose: matchedDose,
              thresholdMcg: adequacyMcg,
              thresholdMg: adequacyMg,
            )
          : CoverageLevel.none;

      results.add(
        DepletionMatch(
          depletionId: depId,
          drugDisplayName: drugDisplayName,
          drugClassId: drugId,
          nutrientName: nutrient['standard_name']?.toString() ?? '',
          nutrientCanonicalId: canonicalId,
          depletionType: depletionType,
          severity: dep['severity']?.toString() ?? 'moderate',
          evidenceLevel: dep['evidence_level']?.toString() ?? 'ungraded',
          mechanism: dep['mechanism']?.toString() ?? '',
          recommendation: dep['recommendation']?.toString() ?? '',
          sources: sources,
          onsetTimeline: dep['onset_timeline']?.toString(),
          watchThresholdDays: watchThresholdDays,
          watchBasis: watchBasis,
          clinicalImpact: dep['clinical_impact']?.toString(),
          alertHeadline: dep['alert_headline']?.toString(),
          alertBody: dep['alert_body']?.toString(),
          acknowledgementNote: dep['acknowledgement_note']?.toString(),
          monitoringTipShort: dep['monitoring_tip_short']?.toString(),
          foodSourcesShort: dep['food_sources_short']?.toString(),
          adequacyThresholdMcg: adequacyMcg,
          adequacyThresholdMg: adequacyMg,
          detectedAmount: matchedDose?.doseAmount,
          detectedUnit: matchedDose?.doseUnit,
          citationReviewStatus: reviewStatus,
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
    // amountInMass folds every mcg spelling (mcg / µg U+00B5 / μg U+03BC /
    // ug) to the same canonical unit before comparing, so both micro-sign
    // variants convert correctly here (the old hand-rolled check only
    // matched U+03BC, silently missing U+00B5).
    //
    // IU conversion is nutrient-specific (vitamin A/D/E each have
    // different factors). We intentionally don't convert here — the
    // pipeline normalizes to mass units before emission for most
    // supplements. amountInMass declines (returns null) for IU, so the
    // caller treats IU doses as partial.
    return amountInMass(amount.toDouble(), from: unit, to: 'mcg');
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

  static DepletionSource? _parseSource(Map<String, dynamic> source) {
    final url = source['url']?.toString().trim() ?? '';
    if (url.isEmpty) return null;
    final sourceType = source['source_type']?.toString().trim() ?? '';
    final authoredLabel = source['label']?.toString().trim() ?? '';
    final label = authoredLabel.isNotEmpty
        ? authoredLabel
        : sourceType.isNotEmpty
        ? sourceType.replaceAll('_', ' ')
        : 'Source';
    return DepletionSource(sourceType: sourceType, label: label, url: url);
  }

  /// Parse the optional curated watch threshold, fail-closed.
  ///
  /// Four conditions must ALL hold before a threshold is honoured:
  ///   1. `watch_threshold_days` is a positive whole number of days,
  ///   2. `watch_basis` cites the evidence for it, and
  ///   3. `watch_review_status` is exactly `approved`, and
  ///   4. `watch_approver` identifies the reviewer.
  ///
  /// Condition 3 is the clinical sign-off gate, mirroring
  /// `citation_review_status`: a drafted threshold ships as `proposed` and is
  /// completely inert until a reviewer approves it. Anything else — a missing
  /// status, `proposed`, `rejected`, or an unknown future value — fails closed.
  ///
  /// A non-integer value is dropped rather than rounded. Silently rounding
  /// would manufacture a clinical timeline no reviewer authored.
  static ({int? watchThresholdDays, String? watchBasis}) _parseWatchThreshold(
    Map<String, dynamic> dep,
  ) {
    const empty = (watchThresholdDays: null, watchBasis: null);
    final status = dep['watch_review_status']?.toString().trim().toLowerCase();
    if (status != 'approved') return empty;
    final raw = dep['watch_threshold_days'];
    if (raw is! int || raw <= 0) return empty;
    final basis = dep['watch_basis']?.toString().trim();
    if (basis == null || basis.isEmpty) return empty;
    final approver = dep['watch_approver']?.toString().trim();
    if (approver == null || approver.isEmpty) return empty;
    return (watchThresholdDays: raw, watchBasis: basis);
  }

  static String _normalizeDepletionType(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    return switch (value) {
      'functional_antagonism' => 'functional_antagonism',
      'monitoring_stability' => 'monitoring_stability',
      'condition_related' => 'condition_related',
      'supplement_interaction' => 'supplement_interaction',
      _ => 'depletion',
    };
  }

  static bool _isSupplementCoverageRelevant(String depletionType) {
    return depletionType == 'depletion' || depletionType == 'condition_related';
  }
}

/// Word-boundary-ish bidirectional name match for the legacy
/// display-name fallback (rows with no structured drug/class ref).
///
/// The shorter of the two names must be at least 5 characters and must
/// appear in the longer one as a whole word (bounded by non-letters),
/// so e.g. "iron" never matches "environ" or "ironwood". Both inputs
/// are expected lowercased.
bool legacyDrugNameMatches(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  final shorter = a.length <= b.length ? a : b;
  final longer = identical(shorter, a) ? b : a;
  if (shorter.length < 5) return false;
  final pattern = RegExp(
    '(^|[^a-z0-9])${RegExp.escape(shorter)}([^a-z0-9]|\$)',
  );
  return pattern.hasMatch(longer);
}
