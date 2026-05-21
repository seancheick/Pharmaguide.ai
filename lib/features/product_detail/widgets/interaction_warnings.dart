import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/core/widgets/pg_interaction_card.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// v6.0 — user's declared profile flags (post_op_recovery,
  /// hypoglycemia_history, bleeding_history) plus the derived
  /// reproductive flags (pregnant, breastfeeding, trying_to_conceive,
  /// surgery_scheduled — derived by [ProfileState.evaluatorProfileFlags]
  /// from the corresponding condition IDs).
  final Set<String> userProfileFlags;

  const InteractionWarningsList({
    super.key,
    required this.warnings,
    this.userConditions = const {},
    this.userDrugClasses = const {},
    this.userProfileFlags = const {},
  });

  static List<InteractionWarning> sortBySeverity(
    List<InteractionWarning> input,
  ) {
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
    Set<String> userProfileFlags = const <String>{},
  }) {
    final applies = <InteractionWarning>[];
    final other = <InteractionWarning>[];
    for (final w in loud) {
      if (w.matchesProfile(
        userConditions: userConditions,
        userDrugClasses: userDrugClasses,
        userProfileFlags: userProfileFlags,
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
                  const SizedBox(height: AppTheme.space2),
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
    final (loud, safeTier) = InteractionWarningsList._partitionSafeTier(sorted);

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
    final hasProfile =
        widget.userConditions.isNotEmpty ||
        widget.userDrugClasses.isNotEmpty ||
        widget.userProfileFlags.isNotEmpty;

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
      userProfileFlags: widget.userProfileFlags,
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
            onToggle: () => setState(() => _otherExpanded = !_otherExpanded),
            previewLabels: InteractionWarning.previewLabelsForWarnings(other),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  border: Border.all(color: scheme.outlineVariant, width: 0.8),
                ),
                child: Text(
                  '$count',
                  style: AppTheme.numeric(
                    TextStyle(
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
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    border: Border.all(
                      color: scheme.outlineVariant,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '$count',
                    style: AppTheme.numeric(
                      TextStyle(
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
                  duration: AppMotion.fast,
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
          duration: AppMotion.fast,
          curve: AppMotion.standard,
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
            const SizedBox(height: AppTheme.space4),
            Text(
              'Flagged by the pipeline as low overall concern.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTheme.space16),
            ...items.map(
              (w) => Padding(
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
                      const SizedBox(height: AppTheme.space2),
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
              ),
            ),
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
              const SizedBox(height: AppTheme.space4),
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
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusFull,
                            ),
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
