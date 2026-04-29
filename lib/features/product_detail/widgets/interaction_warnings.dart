import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_interaction_card.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:url_launcher/url_launcher.dart';

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
///   `title` / `mechanism` / `management` when null.
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

  /// Authored body copy (layperson-facing). Falls back to [mechanism]
  /// if null. Pipeline validator enforces conditional framing for
  /// avoid/contraindicated severity.
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
  String? get conditionId =>
      conditionIds.isEmpty ? null : conditionIds.first;

  /// First drug-class id — convenience accessor, see [conditionId].
  String? get drugClassId =>
      drugClassIds.isEmpty ? null : drugClassIds.first;

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

  /// Display-ready headline — prefers authored [alertHeadline] over
  /// the derived [title]. Use this in render code.
  String get displayHeadline => alertHeadline ?? title;

  /// Display-ready body — prefers authored [alertBody] over the
  /// derived [mechanism]. Use this in render code.
  String get displayBody => alertBody ?? mechanism;

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
    final String? alertHeadline = (json['alert_headline'] ??
            json['safety_warning_one_liner'] ??
            json['safety_summary_one_liner'] ??
            json['brand_trust_summary'])
        ?.toString();
    final String? alertBody = (json['alert_body'] ??
            json['safety_warning'] ??
            json['safety_summary'])
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

    return InteractionWarning(
      severity: Severity.fromString(json['severity']?.toString() ?? 'safe'),
      severityContextual: sevContextual,
      displayModeDefault: json['display_mode_default']?.toString(),
      evidenceLevel: EvidenceLevel.fromString(
          json['evidence_level']?.toString() ?? 'theoretical'),
      title: json['title']?.toString() ?? '',
      mechanism: (json['detail'] ?? json['mechanism'])?.toString() ?? '',
      management: (json['action'] ?? json['management'])?.toString() ?? '',
      sourceUrls: urls,
      alertHeadline: alertHeadline,
      alertBody: alertBody,
      informationalNote: json['informational_note']?.toString(),
      conditionIds: _coerceStringList(
        json['condition_ids'], json['condition_id']),
      drugClassIds: _coerceStringList(
        json['drug_class_ids'], json['drug_class_id']),
      banContext: json['ban_context']?.toString(),
      clinicalRisk: json['clinical_risk']?.toString(),
      mechanismOfHarm: json['mechanism_of_harm']?.toString(),
      populationWarnings: popWarnings,
      doseThresholdEvaluation: doseEval,
      regulatoryDate: json['regulatory_date']?.toString() ??
          json['date']?.toString(),
      regulatoryDateLabel: json['regulatory_date_label']?.toString(),
      additiveCategory: json['category']?.toString(),
      allergenPrevalence: json['prevalence']?.toString(),
      supplementContext: json['supplement_context']?.toString(),
      identifiers: identifiers,
      ingredientName: json['ingredient_name']?.toString(),
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
  /// A profile match means the pipeline rule applies to this user —
  /// their declared conditions or drug classes intersect the rule's
  /// trigger tags. Used by the profile-gated filter on the product
  /// detail screen.
  bool matchesProfile({
    required Set<String> userConditions,
    required Set<String> userDrugClasses,
  }) {
    // FLTR-1 — check every tag in the plural arrays, not just the
    // first. A warning with condition_ids: ['pregnancy', 'lactation']
    // must match a user carrying either one.
    if (conditionIds.any(userConditions.contains)) return true;
    if (drugClassIds.any(userDrugClasses.contains)) return true;
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
    return '${conditions.join(',')}|${drugClasses.join(',')}|$headline|$body';
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
      if (existing == null ||
          w.severity.weight > existing.severity.weight) {
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
        .map(
          (part) => part[0].toUpperCase() + part.substring(1).toLowerCase(),
        )
        .join(' ');
  }
}

/// Renders sorted interaction warnings from the detail blob.
/// Sorted by severity (contraindicated first → safe last).
///
/// FLTR-18: when the user has any profile data (conditions or
/// drug classes), warnings are split into two sections:
///   - "Applies to you" — profile-matched, expanded, full cards
///   - "Other precautions" — everything else, collapsed with a count
/// When no profile is set, falls back to a single combined section
/// so the widget still works in contexts that don't thread a
/// profile (tests, preview surfaces).
class InteractionWarningsList extends StatefulWidget {
  final List<InteractionWarning> warnings;

  /// FLTR-18 — user's declared conditions (e.g. {'pregnancy',
  /// 'diabetes'}). Used to partition warnings into profile-matched
  /// vs generic precaution buckets. Empty set disables the split
  /// (widget falls back to a single combined list).
  final Set<String> userConditions;

  /// FLTR-18 — user's declared drug classes (e.g. {'statins',
  /// 'anticoagulants'}). Same split contract as [userConditions].
  final Set<String> userDrugClasses;

  const InteractionWarningsList({
    super.key,
    required this.warnings,
    this.userConditions = const {},
    this.userDrugClasses = const {},
  });

  static List<InteractionWarning> sortBySeverity(
      List<InteractionWarning> input) {
    final sorted = List<InteractionWarning>.from(input);
    sorted.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
    return sorted;
  }

  /// FLTR-14 — partition warnings so `Severity.safe` never takes a
  /// full card and is instead summarized in a collapsed row.
  /// "informational" tier stays in the main list (it's still
  /// context worth reading); only `safe` items (flow-agent notes,
  /// low-overall-concern notes) get collapsed.
  static (List<InteractionWarning> loud, List<InteractionWarning> safeTier)
      _partitionSafeTier(List<InteractionWarning> sorted) {
    final loud = <InteractionWarning>[];
    final safeTier = <InteractionWarning>[];
    for (final w in sorted) {
      if (w.severity == Severity.safe) {
        safeTier.add(w);
      } else {
        loud.add(w);
      }
    }
    return (loud, safeTier);
  }

  /// FLTR-18 — partition loud warnings by profile match. `applies`
  /// contains entries where the warning's condition_ids OR
  /// drug_class_ids overlap the user's declared profile; `other`
  /// contains everything else that survived the upstream filter
  /// (pipeline told us to show regardless — critical / informational
  /// / legacy generic).
  static (List<InteractionWarning> applies, List<InteractionWarning> other)
      _partitionByProfile(
    List<InteractionWarning> loud, {
    required Set<String> userConditions,
    required Set<String> userDrugClasses,
  }) {
    final applies = <InteractionWarning>[];
    final other = <InteractionWarning>[];
    for (final w in loud) {
      if (w.matchesProfile(
        userConditions: userConditions,
        userDrugClasses: userDrugClasses,
      )) {
        applies.add(w);
      } else {
        other.add(w);
      }
    }
    return (applies, other);
  }

  @override
  State<InteractionWarningsList> createState() =>
      _InteractionWarningsListState();
}

class _InteractionWarningsListState extends State<InteractionWarningsList> {
  /// FLTR-18 — "Other precautions" starts collapsed. The whole
  /// point of the split is that generic precautions don't
  /// dominate the stack visually; the user can expand on demand.
  bool _otherExpanded = false;

  void _showCitations(BuildContext context, InteractionWarning warning) {
    PGModal.bottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (ctx) => _CitationsSheet(warning: warning),
    );
  }

  void _showSafeTierSheet(
    BuildContext context,
    List<InteractionWarning> items,
  ) {
    PGModal.bottomSheet<void>(
      context: context,
      showDragHandle: false,
      builder: (ctx) => _LowConcernNotesSheet(items: items),
    );
  }

  @override
  Widget build(BuildContext context) {
    final warnings = widget.warnings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // -----------------------------------------------------------------
    // Empty state — "no known interactions." This is GOOD news in a
    // pharma app, so treat it as a positive-tinted card, not a dry
    // single line of gray text.
    // -----------------------------------------------------------------
    if (warnings.isEmpty) {
      return PGCard(
        variant: PGCardVariant.recessed,
        padding: const EdgeInsets.all(AppTheme.space16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.severitySafe.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppTheme.severitySafe,
                size: 20,
              ),
            ),
            const SizedBox(width: AppTheme.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No known interactions',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Based on your current health profile and this product.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final sorted = InteractionWarningsList.sortBySeverity(warnings);
    // FLTR-14 — keep `Severity.safe` out of the main card stack. Flow
    // agents, low-concern excipient notes, etc. render as a single
    // collapsed summary row below the real warnings instead of
    // taking equal visual weight to clinical alerts.
    final (loud, safeTier) =
        InteractionWarningsList._partitionSafeTier(sorted);

    // No loud warnings — render only the low-concern summary if any
    // safe-tier items exist; else fall through to the empty-state
    // card already handled above.
    if (loud.isEmpty) {
      return _LowConcernSummaryRow(
        items: safeTier,
        onTap: () => _showSafeTierSheet(context, safeTier),
      );
    }

    // FLTR-18 — split only when the user has ANY profile data.
    // Without profile we have nothing to match against; keep the
    // single combined list so unprofiled surfaces (tests, preview
    // pages) don't collapse everything into "Other" and hide it.
    final hasProfile = widget.userConditions.isNotEmpty ||
        widget.userDrugClasses.isNotEmpty;

    if (!hasProfile) {
      // Existing pre-FLTR-18 rendering: one section, all loud cards,
      // safe-tier summary below. Kept verbatim for backward compat.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(context, 'Interaction warnings', loud.length),
          ..._loudCards(loud),
          if (safeTier.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space12),
            _LowConcernSummaryRow(
              items: safeTier,
              onTap: () => _showSafeTierSheet(context, safeTier),
            ),
          ],
        ],
      );
    }

    // FLTR-18 split — profile is set, so we can personalize.
    final (applies, other) = InteractionWarningsList._partitionByProfile(
      loud,
      userConditions: widget.userConditions,
      userDrugClasses: widget.userDrugClasses,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (applies.isNotEmpty) ...[
          _sectionHeader(
            context,
            'Applies to you',
            applies.length,
            subtitle: 'Based on your saved profile.',
          ),
          ..._loudCards(applies),
        ],
        if (other.isNotEmpty) ...[
          if (applies.isNotEmpty) const SizedBox(height: AppTheme.space20),
          _OtherPrecautionsSection(
            count: other.length,
            expanded: _otherExpanded,
            onToggle: () =>
                setState(() => _otherExpanded = !_otherExpanded),
            previewLabels:
                InteractionWarning.previewLabelsForWarnings(other),
            cards: _loudCards(other),
          ),
        ],
        if (safeTier.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space12),
          _LowConcernSummaryRow(
            items: safeTier,
            onTap: () => _showSafeTierSheet(context, safeTier),
          ),
        ],
      ],
    );
  }

  /// Section header row with a count pill. Used by both the
  /// no-profile combined path and the FLTR-18 "Applies to you"
  /// section so the style stays identical.
  Widget _sectionHeader(
    BuildContext context,
    String label,
    int count, {
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                label,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: AppTheme.space8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusFull),
                  border: Border.all(
                    color: scheme.outlineVariant,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '$count',
                  style: AppTheme.numeric(
                    TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Render the card stack for a list of loud warnings. Shared
  /// between the no-profile combined path and the FLTR-18 sections.
  List<Widget> _loudCards(List<InteractionWarning> items) {
    return List.generate(items.length, (i) {
      final w = items[i];
      // Contamination-recall entries get a distinct banner prefix —
      // the copy describes a product recall, not a chemistry ban, so
      // the framing in the card header shifts accordingly. See
      // scripts/safety_copy_exemplars/ADR_contamination_recall_ban_context.md
      // in the pipeline repo for the authoring contract.
      final title = w.banContext == 'contamination_recall'
          ? 'Recalled: ${w.displayHeadline}'
          : w.displayHeadline;
      return Padding(
        padding: EdgeInsets.only(
          bottom: i == items.length - 1 ? 0 : AppTheme.space12,
        ),
        child: PGInteractionCard(
          severity: w.severity,
          evidenceLevel: w.evidenceLevel,
          // displayHeadline / displayBody prefer Path-C-authored copy
          // (Dr. Pham, 2026-04-17/18) over derived pipeline strings.
          title: title,
          mechanism: w.displayBody,
          management: w.management,
          sources: w.sourceUrls,
          // Top-severity card starts expanded — user sees the worst
          // interaction's full details without needing to tap.
          initiallyExpanded: i == 0 && w.severity.weight >= 3,
          onSourceTap: w.sourceUrls.isEmpty
              ? null
              : () => _showCitations(context, w),
        ),
      );
    });
  }
}

/// FLTR-18 — "Other precautions" section. Collapsed by default so
/// generic precautions don't dominate the stack; tap the header
/// row to reveal the individual cards. Count pill shows the total
/// so the user knows what's behind the chevron.
class _OtherPrecautionsSection extends StatelessWidget {
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final List<String> previewLabels;
  final List<Widget> cards;

  const _OtherPrecautionsSection({
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.previewLabels,
    required this.cards,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = count == 1
        ? '1 general precaution'
        : '$count general precautions';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space12,
              vertical: AppTheme.space12,
            ),
            child: Row(
              children: [
                Text(
                  'Other precautions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: AppTheme.space8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusFull),
                    border: Border.all(
                      color: scheme.outlineVariant,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '$count',
                    style: AppTheme.numeric(
                      TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!expanded)
          Padding(
            padding: const EdgeInsets.only(
              left: AppTheme.space12,
              bottom: AppTheme.space4,
              right: AppTheme.space12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'General precautions that do not currently match your saved profile.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                if (previewLabels.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.space8),
                  Wrap(
                    spacing: AppTheme.space8,
                    runSpacing: AppTheme.space8,
                    children: previewLabels
                        .map(
                          (preview) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.space12,
                              vertical: AppTheme.space6,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusFull,
                              ),
                              border: Border.all(
                                color: scheme.outlineVariant,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              preview,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: AppTheme.space8),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: AppTheme.space8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: cards,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// FLTR-14 — collapsed summary row standing in for all
/// `Severity.safe` warnings. Tap → opens a sheet listing the
/// individual items. Renders nothing when the group is empty so
/// callers don't need to guard.
class _LowConcernSummaryRow extends StatelessWidget {
  final List<InteractionWarning> items;
  final VoidCallback onTap;

  const _LowConcernSummaryRow({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = items.length;
    final label = count == 1
        ? '1 low-concern note'
        : '$count low-concern notes';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space12,
          vertical: AppTheme.space8,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppTheme.space8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet revealing the individual items behind a
/// [_LowConcernSummaryRow]. Deliberately minimal — these are
/// pipeline-classified as low-concern, so the sheet is a reference,
/// not an alert surface.
class _LowConcernNotesSheet extends StatelessWidget {
  final List<InteractionWarning> items;

  const _LowConcernNotesSheet({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space20,
          AppTheme.space16,
          AppTheme.space20,
          AppTheme.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Low-concern notes',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Flagged by the pipeline as low overall concern.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTheme.space16),
            ...items.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.space12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.displayHeadline,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (w.displayBody.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          w.displayBody,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Citations bottom sheet — shown when user taps the "N sources" chip.
// ---------------------------------------------------------------------------

class _CitationsSheet extends StatelessWidget {
  final InteractionWarning warning;

  const _CitationsSheet({required this.warning});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          // Bottom padding clears the frosted nav bar.
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space8,
            AppTheme.space20,
            AppTheme.space32 + kPGNavBarHeight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Sources',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Clinical references backing this interaction warning.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.space20),
              // Each source as its own tappable PGCard
              ...warning.sourceUrls.asMap().entries.map((entry) {
                final idx = entry.key;
                final url = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.space8),
                  child: PGCard(
                    padding: const EdgeInsets.all(AppTheme.space12),
                    onTap: () {
                      final uri = Uri.tryParse(url);
                      if (uri == null) return;
                      // Fire-and-forget — if the OS can't handle the URL
                      // we silently no-op. The scheme is always https from
                      // the pipeline so launch failures are extremely rare;
                      // we deliberately don't await to keep the tap snappy.
                      unawaited(
                        launchUrl(uri, mode: LaunchMode.externalApplication),
                      );
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusFull),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${idx + 1}',
                            style: AppTheme.numeric(
                              theme.textTheme.labelLarge!.copyWith(
                                fontSize: 13,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTheme.space12),
                        Expanded(
                          child: Text(
                            _prettyHost(url),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppTheme.space8),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  /// Returns a prettier label for a URL — host + last path segment, so
  /// `https://pubmed.ncbi.nlm.nih.gov/12345678/abc` becomes
  /// `pubmed.ncbi.nlm.nih.gov / abc`.
  String _prettyHost(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final host = uri.host.isEmpty ? url : uri.host;
    final lastSeg = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '')
        : '';
    if (lastSeg.isEmpty) return host;
    return '$host  ·  $lastSeg';
  }
}
