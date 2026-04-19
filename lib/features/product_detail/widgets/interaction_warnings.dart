import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_interaction_card.dart';
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

  /// The condition that triggers this warning (e.g. 'pregnancy', 'diabetes').
  /// Null if the warning is not condition-specific (e.g. drug class warning).
  final String? conditionId;

  /// The drug class that triggers this warning (e.g. 'anticoagulants').
  /// Null if the warning is not drug-class-specific.
  final String? drugClassId;

  /// Pipeline `ban_context` for banned_recalled warnings — one of
  /// `substance`, `adulterant_in_supplements`, `watchlist`,
  /// `export_restricted`, `contamination_recall`. Drives the banner
  /// framing: recall-voiced for `contamination_recall`, substance-
  /// voiced for `substance`, etc. Null for non-banned warning types.
  final String? banContext;

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
    this.conditionId,
    this.drugClassId,
    this.banContext,
  });

  /// Parse from raw JSON map (from detail blob `warnings` list).
  ///
  /// Pipeline emits fields: `detail`, `action`, `sources`, `condition_id`,
  /// `drug_class_id`, `display_mode_default`, `severity_contextual`,
  /// `alert_headline`, `alert_body`, `informational_note`. Legacy aliases
  /// `mechanism`/`management`/`source_urls` are also accepted for backward
  /// compat with older cached blobs.
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
      conditionId: json['condition_id']?.toString(),
      drugClassId: json['drug_class_id']?.toString(),
      banContext: json['ban_context']?.toString(),
    );
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
    if (conditionId != null &&
        conditionId!.isNotEmpty &&
        userConditions.contains(conditionId)) {
      return true;
    }
    if (drugClassId != null &&
        drugClassId!.isNotEmpty &&
        userDrugClasses.contains(drugClassId)) {
      return true;
    }
    return false;
  }
}

/// Renders sorted interaction warnings from the detail blob.
/// Sorted by severity (contraindicated first → safe last).
class InteractionWarningsList extends StatelessWidget {
  final List<InteractionWarning> warnings;

  const InteractionWarningsList({super.key, required this.warnings});

  static List<InteractionWarning> sortBySeverity(
      List<InteractionWarning> input) {
    final sorted = List<InteractionWarning>.from(input);
    sorted.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
    return sorted;
  }

  void _showCitations(BuildContext context, InteractionWarning warning) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => _CitationsSheet(warning: warning),
    );
  }

  @override
  Widget build(BuildContext context) {
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

    final sorted = sortBySeverity(warnings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header row with count pill
        Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.space12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Interaction warnings',
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
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  border: Border.all(
                    color: scheme.outlineVariant,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '${sorted.length}',
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
        ),

        // Stack of interaction cards with breathing room between
        ...List.generate(sorted.length, (i) {
          final w = sorted[i];
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
              bottom: i == sorted.length - 1 ? 0 : AppTheme.space12,
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
        }),
      ],
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
