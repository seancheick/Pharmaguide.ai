import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/services/warnings/profile_gate_evaluator.dart';

/// A single interaction warning entry parsed from the detail blob.
///
/// This class is public because [product_detail_screen.dart] parses it
/// directly from the detail blob and passes a `List<InteractionWarning>`
/// into [InteractionWarningsList].
///
/// Pipeline safety-copy contract (schema v5.2, 2026-04-17):
/// - `displayModeDefault` — how the warning should render when NO user
///   profile match exists. Values: `critical` (always show),
///   `informational` (neutral note), `suppress` (hide without profile
///   match). Null on older blobs — treat as `informational`. See
///   `scripts/SAFETY_DATA_PATH_C_PLAN.md` in the pipeline repo.
/// - `severityContextual` — downgraded severity to paint in the profile-
///   less default view (e.g., `avoid` → `informational` pill). Equal to
///   [severity] for contraindicated and substance-level hazards.
/// - `alertHeadline` / `alertBody` / `informationalNote` — authored
///   layperson copy. Optional during authoring transition; fall back to
///   `title` / short informational copy / clinical mechanism when null.
class InteractionWarning {
  final Severity severity;

  /// The severity to render when no user profile match was found.
  /// Downgraded by the pipeline to a calmer tier for avoid/caution
  /// rules. Null on older blobs predating schema 5.2.
  final Severity? severityContextual;

  /// How the warning should display when NO user profile matches.
  /// Null on older blobs (pre-5.2) — treated as `informational`.
  final String? displayModeDefault;

  final EvidenceLevel evidenceLevel;
  final String title;
  final String mechanism;
  final String management;
  final List<String> sourceUrls;

  /// Authored banner headline (layperson-facing). Falls back to [title]
  /// if null. Pipeline validator enforces 20-60 chars, no all-caps.
  final String? alertHeadline;

  /// Authored body copy (layperson-facing). Falls back to
  /// [informationalNote], then [mechanism] if null. Pipeline validator
  /// enforces conditional framing for avoid/contraindicated severity.
  final String? alertBody;

  /// Authored neutral note shown when the rule is material but no user
  /// profile match. Validator enforces 40-120 chars with no imperative
  /// verbs.
  final String? informationalNote;

  /// Conditions that trigger this warning (e.g. ['pregnancy', 'lactation']).
  /// Empty when the warning is not condition-specific. Schema v5.2+ emits
  /// the plural `condition_ids[]`; legacy blobs carrying singular
  /// `condition_id` are lifted into a one-element list by [fromJson].
  final List<String> conditionIds;

  /// Drug classes that trigger this warning (e.g. ['anticoagulants']).
  /// Empty when the warning is not drug-class-specific. Schema v5.2+
  /// emits the plural `drug_class_ids[]`; legacy singular is lifted
  /// into a one-element list by [fromJson].
  final List<String> drugClassIds;

  /// First condition id — convenience accessor preserved for callers
  /// that only need a single representative tag (search indices, logs,
  /// etc.). Prefer [conditionIds] for membership checks — a warning
  /// can carry multiple tags and [matchesProfile] correctly checks all.
  String? get conditionId => conditionIds.isEmpty ? null : conditionIds.first;

  /// First drug-class id — convenience accessor, see [conditionId].
  String? get drugClassId => drugClassIds.isEmpty ? null : drugClassIds.first;

  /// Pipeline `ban_context` for banned_recalled warnings — one of
  /// `substance`, `adulterant_in_supplements`, `watchlist`,
  /// `export_restricted`, `contamination_recall`. Drives the banner
  /// framing: recall-voiced for `contamination_recall`, substance-
  /// voiced for `substance`, etc. Null for non-banned warning types.
  final String? banContext;

  /// Pipeline `clinical_risk` for banned_recalled / high_risk_ingredient
  /// warnings — one of `critical`, `high`, `moderate`, `low`. Paired
  /// with [severity] but distinct: severity drives display tier, clinical
  /// risk drives medical-evidence weight (Dr Pham safety taxonomy).
  final String? clinicalRisk;

  /// Pipeline `mechanism_of_harm` for harmful_additive warnings —
  /// technical explanation (e.g. "Nanoparticle concerns in gut
  /// epithelium"). Surfaces in the expanded warning detail sheet.
  final String? mechanismOfHarm;

  /// Pipeline `population_warnings` for harmful_additive warnings —
  /// list of at-risk groups with context (e.g. "Children — immature gut
  /// barrier", "People with IBD — may aggravate inflammation"). Rendered
  /// as bullet list in expanded detail.
  final List<String> populationWarnings;

  /// Pipeline `dose_threshold_evaluation` for interaction /
  /// drug_interaction warnings — structured block describing trigger
  /// threshold (e.g. only active at >1g/day). Preserved raw so the
  /// detail sheet can render conditional phrasing.
  final Map<String, dynamic>? doseThresholdEvaluation;

  /// Pipeline `regulatory_date` + `regulatory_date_label` for
  /// banned_recalled / high_risk_ingredient warnings — "First FDA
  /// enforcement action: 2019-04" style context.
  final String? regulatoryDate;
  final String? regulatoryDateLabel;

  /// Pipeline `category` on harmful_additive — "colorant", "sweetener",
  /// "preservative" etc. Lets the UI group additives by class.
  final String? additiveCategory;

  /// Pipeline `prevalence` on allergen warnings — one of `high`,
  /// `moderate`, `low`. Paired with severity — e.g. a high-prevalence
  /// allergen (peanut) renders differently than a low one (sesame).
  final String? allergenPrevalence;

  /// Pipeline `supplement_context` on allergen warnings — free-form
  /// copy (e.g. "Common emulsifier in soft-gels"). Shown under the
  /// title on the allergen card.
  final String? supplementContext;

  /// Pipeline `identifiers` object — {cui, unii, cas, pubchem_cid}
  /// for the subject ingredient/substance. Preserved raw so the
  /// ingredient-detail drawer can render medical codes (CUI lookup).
  final Map<String, dynamic>? identifiers;

  /// Pipeline `ingredient_name` — the ingredient this warning is
  /// about (e.g., "Niacin", "Chromium"). Useful for linking a
  /// warning back to its ingredient row in UI (e.g., ingredient
  /// drawer cross-reference). Null when the warning is not
  /// ingredient-specific (e.g., manufacturer trust violations).
  final String? ingredientName;

  /// v6.0 `profile_gate` — deterministic predicate the evaluator runs
  /// against (user_profile, product_context) to decide whether this
  /// alert should fire. Replaces the inferred set-intersection over
  /// [conditionIds] / [drugClassIds] when present. Null on pre-v6.0
  /// blobs (legacy intersection logic still applies as fallback in
  /// [matchesProfile]).
  ///
  /// See `lib/services/warnings/profile_gate_evaluator.dart` for the
  /// Dart reference impl, kept in lockstep with
  /// `dsld_clean/scripts/profile_gate_evaluator.py` via the shared
  /// drift-contract fixture (`test/fixtures/profile_gate/`).
  final Map<String, dynamic>? profileGate;

  /// Display-ready headline — prefers authored [alertHeadline] over
  /// the derived [title]. Use this in render code.
  String get displayHeadline => alertHeadline ?? title;

  /// Display-ready body — prefers authored [alertBody], then the short
  /// neutral [informationalNote], over the derived [mechanism]. Use this
  /// in render code.
  String get displayBody => alertBody ?? informationalNote ?? mechanism;

  /// Smart-flagging axes (pipeline batch diabetes-01+). Null on older blobs.
  /// `direction`: harmful | beneficial | neutral | unknown.
  /// `materiality`: presence | dose_dependent | unknown.
  /// `doseFloorStatus`: below | at_or_above | null — pipeline-computed against
  /// the rule's form-scoped `min_effective_dose`. Null = floor absent, or dose
  /// / form unknown → fail open (the warning fires).
  final String? direction;
  final String? materiality;
  final String? doseFloorStatus;

  const InteractionWarning({
    required this.severity,
    required this.evidenceLevel,
    required this.title,
    required this.mechanism,
    required this.management,
    this.sourceUrls = const [],
    this.severityContextual,
    this.displayModeDefault,
    this.alertHeadline,
    this.alertBody,
    this.informationalNote,
    this.conditionIds = const [],
    this.drugClassIds = const [],
    this.banContext,
    this.clinicalRisk,
    this.mechanismOfHarm,
    this.populationWarnings = const [],
    this.doseThresholdEvaluation,
    this.regulatoryDate,
    this.regulatoryDateLabel,
    this.additiveCategory,
    this.allergenPrevalence,
    this.supplementContext,
    this.identifiers,
    this.ingredientName,
    this.profileGate,
    this.direction,
    this.materiality,
    this.doseFloorStatus,
  });

  /// Parse from raw JSON map (from detail blob `warnings` list).
  ///
  /// Pipeline emits fields: `detail`, `action`, `sources`, `condition_ids`,
  /// `drug_class_ids`, `display_mode_default`, `severity_contextual`,
  /// `alert_headline`, `alert_body`, `informational_note`.
  ///
  /// Sprint E1.4.1 (pipeline 2026-04-22): `condition_id` / `drug_class_id`
  /// migrated to plural arrays `condition_ids[]` / `drug_class_ids[]`.
  /// This parser accepts both shapes — plural wins; singular is used as
  /// a fallback for blobs cached pre-migration.
  ///
  /// Legacy aliases `mechanism`/`management`/`source_urls` are also
  /// accepted for backward compat with older cached blobs.
  factory InteractionWarning.fromJson(Map<String, dynamic> json) {
    final rawUrls = json['sources'] ?? json['source_urls'];
    final urls = rawUrls is List
        ? rawUrls.map((e) => e.toString()).toList()
        : <String>[];

    final sevContextualRaw = json['severity_contextual']?.toString();
    final sevContextual =
        (sevContextualRaw != null && sevContextualRaw.isNotEmpty)
        ? Severity.fromString(sevContextualRaw)
        : null;

    // Authored-copy field normalization — different warning types carry
    // the Path C fields under different names. We collapse them into the
    // unified alertHeadline / alertBody here so the render side never has
    // to branch on type:
    //   interaction warnings      → alert_headline / alert_body
    //   banned_recalled warnings  → safety_warning_one_liner / safety_warning
    //   harmful_additive warnings → safety_summary_one_liner / safety_summary
    //   manufacturer violations   → brand_trust_summary / (no long body)
    final String? alertHeadline =
        (json['alert_headline'] ??
                json['safety_warning_one_liner'] ??
                json['safety_summary_one_liner'] ??
                json['brand_trust_summary'])
            ?.toString();
    final String? alertBody =
        (json['alert_body'] ?? json['safety_warning'] ?? json['safety_summary'])
            ?.toString();

    // Dr Pham's user-facing safety fields — propagated by the enricher
    // from banned_recalled / harmful_additives / ingredient_interaction_rules /
    // allergens data files. These are the medical-evidence breadcrumbs the
    // detail-sheet rendering depends on (population_warnings bullet list,
    // clinical_risk-driven banner tint, regulatory_date context line, etc.).
    final rawPopWarnings = json['population_warnings'];
    final popWarnings = rawPopWarnings is List
        ? rawPopWarnings.map((e) => e.toString()).toList()
        : const <String>[];

    final rawDoseEval = json['dose_threshold_evaluation'];
    final doseEval = rawDoseEval is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawDoseEval)
        : null;

    final rawIdentifiers = json['identifiers'];
    final identifiers = rawIdentifiers is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawIdentifiers)
        : null;

    final rawProfileGate = json['profile_gate'];
    final profileGate = rawProfileGate is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawProfileGate)
        : null;

    return InteractionWarning(
      // Fail safe: a warning that arrives with no severity is malformed,
      // not benign. Default to caution (matching the DB-hydration path in
      // interaction_result.dart) so a missing field can never silently
      // drop a real warning to `safe` and out of the actionable bucket.
      severity: Severity.fromString(
        json['severity']?.toString() ?? 'caution',
      ),
      severityContextual: sevContextual,
      displayModeDefault: json['display_mode_default']?.toString(),
      evidenceLevel: EvidenceLevel.fromString(
        json['evidence_level']?.toString() ?? 'ungraded',
      ),
      title: json['title']?.toString() ?? '',
      mechanism: (json['detail'] ?? json['mechanism'])?.toString() ?? '',
      management: (json['action'] ?? json['management'])?.toString() ?? '',
      sourceUrls: urls,
      alertHeadline: alertHeadline,
      alertBody: alertBody,
      informationalNote: json['informational_note']?.toString(),
      conditionIds: _coerceStringList(
        json['condition_ids'],
        json['condition_id'],
      ),
      drugClassIds: _coerceStringList(
        json['drug_class_ids'],
        json['drug_class_id'],
      ),
      banContext: json['ban_context']?.toString(),
      clinicalRisk: json['clinical_risk']?.toString(),
      mechanismOfHarm: json['mechanism_of_harm']?.toString(),
      populationWarnings: popWarnings,
      doseThresholdEvaluation: doseEval,
      regulatoryDate:
          json['regulatory_date']?.toString() ?? json['date']?.toString(),
      regulatoryDateLabel: json['regulatory_date_label']?.toString(),
      additiveCategory: json['category']?.toString(),
      allergenPrevalence: json['prevalence']?.toString(),
      supplementContext: json['supplement_context']?.toString(),
      identifiers: identifiers,
      ingredientName: json['ingredient_name']?.toString(),
      profileGate: profileGate,
      direction: json['direction']?.toString(),
      materiality: json['materiality']?.toString(),
      doseFloorStatus: json['dose_floor_status']?.toString(),
    );
  }

  /// Sprint E1.4.1 compat helper — pipeline migrated singular
  /// condition_id / drug_class_id → plural arrays on 2026-04-22.
  /// FLTR-1 update: return the full list so profile matching checks
  /// every tag, not just the first. Legacy singular is lifted into
  /// a one-element list for blobs cached pre-migration.
  static List<String> _coerceStringList(dynamic plural, dynamic singular) {
    if (plural is List) {
      final out = <String>[];
      for (final e in plural) {
        if (e == null) continue;
        final s = e.toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
      if (out.isNotEmpty) return out;
    }
    if (singular != null) {
      final s = singular.toString().trim();
      if (s.isNotEmpty) return <String>[s];
    }
    return const <String>[];
  }

  /// Does this warning match the given user profile?
  ///
  /// **Primary path (v6.0+)**: when [profileGate] is non-null, delegates
  /// to [evaluateProfileGate] from
  /// `lib/services/warnings/profile_gate_evaluator.dart` — the canonical
  /// evaluator that mirrors the Python reference. This honors `excludes`
  /// blocks (topical aloe, β-carotene, culinary turmeric) and per-rule
  /// gate semantics that the legacy intersection logic cannot express.
  ///
  /// **Fallback path (pre-v6.0 cached blobs)**: legacy set-intersection
  /// over [conditionIds] / [drugClassIds]. This branch is preserved for
  /// blobs cached before the v1.6.0 catalog DB rolled out and exists
  /// purely for backward compatibility — fresh blobs always carry
  /// [profileGate].
  bool matchesProfile({
    required Set<String> userConditions,
    required Set<String> userDrugClasses,
    Set<String> userProfileFlags = const <String>{},
    String? productForm,
    String? nutrientForm,
    num? dosePerDay,
  }) {
    if (profileGate != null) {
      final result = evaluateProfileGate(
        profileGate,
        UserProfile(
          conditions: userConditions,
          drugClasses: userDrugClasses,
          profileFlags: userProfileFlags,
        ),
        ProductContext(
          productForm: productForm,
          nutrientForm: nutrientForm,
          dosePerDay: dosePerDay,
        ),
      );
      return result.fires;
    }
    // FLTR-1 legacy fallback — pre-v6.0 cached blob without profile_gate.
    //
    // TODO(v6.1): remove this entire block ~30 days after the v1.6.0
    // catalog DB ships to production. By then every active user's local
    // detail cache will have rolled over to v1.6.0 blobs which always
    // carry profile_gate.
    //
    // Compat: v6.1.0 split hypoglycemics into 3 subclasses in the user
    // profile, but pre-v1.6.0 cached blobs still reference the old
    // "hypoglycemics" ID. Without this mapping, migrated profiles
    // silently lose diabetes warnings on cached blobs.
    const legacyDrugClassCompat = <String, String>{
      'hypoglycemics_high_risk': 'hypoglycemics',
      'hypoglycemics_lower_risk': 'hypoglycemics',
      'hypoglycemics_unknown': 'hypoglycemics',
    };
    if (conditionIds.any(userConditions.contains)) return true;
    if (drugClassIds.any(userDrugClasses.contains)) return true;
    // Check compat: user has new ID, blob has old ID
    for (final userDc in userDrugClasses) {
      final legacy = legacyDrugClassCompat[userDc];
      if (legacy != null && drugClassIds.contains(legacy)) return true;
    }
    return false;
  }

  /// Composite dedup key for FLTR-12. Two warnings with the same key
  /// represent the same semantic alert and should collapse to one
  /// card even when severity or source differs.
  ///
  /// Severity is DELIBERATELY excluded — "monitor" and "caution"
  /// versions of the same message must collapse together; [dedupe]
  /// picks the highest severity from the group. Type is excluded
  /// because InteractionWarning doesn't persist it and the headline
  /// already discriminates between categories in practice.
  String get _dedupeKey {
    final conditions = [...conditionIds]..sort();
    final drugClasses = [...drugClassIds]..sort();
    final headline = displayHeadline.trim().toLowerCase();
    final body = displayBody.trim().toLowerCase();
    // v6.1: include a stable profile_gate signature so clinically distinct
    // gated rules (e.g. hypoglycemics_high_risk vs lower_risk with different
    // severities) are not collapsed before evaluation.
    var gateKey = '';
    if (profileGate != null) {
      final gateType = profileGate!['gate_type']?.toString() ?? '';
      final requires = profileGate!['requires'];
      final parts = <String>[];
      if (requires is Map) {
        for (final v in requires.values) {
          if (v is List) parts.addAll(v.map((e) => e.toString()));
        }
      }
      parts.sort();
      gateKey = '$gateType:${parts.join(',')}';
    }
    // Smart-flag fields are load-bearing for the emitted-floor gate, which runs
    // AFTER dedupe — so two rows the gate would treat differently (one below-floor
    // suppressible, one firing) must not collapse into one. Identical real
    // duplicates (same warning in both blob lists) still share these values and
    // collapse as before.
    return '${conditions.join(',')}|${drugClasses.join(',')}|$headline|$body|$gateKey'
        '|$direction|$materiality|$doseFloorStatus';
  }

  /// Collapse duplicate warnings into a single entry per [_dedupeKey],
  /// keeping the entry with the highest severity weight. Preserves
  /// first-occurrence order so the rendered list still reads in the
  /// pipeline's intended sequence.
  ///
  /// Real blobs emit duplicates in two ways — both handled here:
  ///   (a) same entry appears in both `warnings[]` and
  ///       `warnings_profile_gated[]` (cross-list)
  ///   (b) pipeline emits the same semantic entry twice inside one
  ///       list (e.g., "Vitamin A / pregnancy" 2× on dsld 15640)
  static List<InteractionWarning> dedupe(
    Iterable<InteractionWarning> warnings,
  ) {
    final best = <String, InteractionWarning>{};
    final firstIndex = <String, int>{};
    var i = 0;
    for (final w in warnings) {
      final k = w._dedupeKey;
      firstIndex.putIfAbsent(k, () => i);
      final existing = best[k];
      if (existing == null || w.severity.weight > existing.severity.weight) {
        best[k] = w;
      }
      i++;
    }
    final keys = best.keys.toList()
      ..sort((a, b) => firstIndex[a]!.compareTo(firstIndex[b]!));
    return [for (final k in keys) best[k]!];
  }

  static List<String> previewLabelsForWarnings(
    Iterable<InteractionWarning> warnings,
  ) {
    final seen = <String>{};
    final labels = <String>[];

    void addLabel(String? raw) {
      final label = raw?.trim();
      if (label == null || label.isEmpty) return;
      final key = label.toLowerCase();
      if (seen.add(key)) {
        labels.add(label);
      }
    }

    for (final warning in warnings) {
      for (final id in warning.conditionIds) {
        addLabel(_humanizePreviewToken(id));
      }
      for (final id in warning.drugClassIds) {
        addLabel(_humanizePreviewToken(id));
      }
      addLabel(warning.ingredientName);
      addLabel(_humanizePreviewToken(warning.additiveCategory));
      if (labels.length >= 3) break;
    }

    return labels.take(3).toList(growable: false);
  }

  static String? _humanizePreviewToken(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
  }
}
