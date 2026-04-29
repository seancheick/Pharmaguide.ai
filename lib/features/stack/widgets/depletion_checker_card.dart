// Depletion Checker Card — shows nutrients depleted by user's medications.
//
// Three-state rendering, calibrated for chronic (not acute) risk:
//
//   all_covered  → calm green header, positive acknowledgements
//                   ("Nice — you're taking B12, which doctors recommend…")
//   partial      → soft amber header, mix of acknowledgements + gentle
//                   suggestions (dose-adequacy bumps, missing nutrients)
//   none_covered → soft amber header, gentle share-not-alarm copy
//                   ("Since you take metformin, here's something worth
//                   knowing over time…")
//
// Tone is deliberately calm. Depletion is chronic (onset months-to-
// years); a stack view should feel informed, not alarmed. See
// scripts/SAFETY_DATA_PATH_C_PLAN.md in the pipeline repo.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:url_launcher/url_launcher.dart';

class DepletionCheckerCard extends StatelessWidget {
  final List<DepletionMatch> depletions;
  final EdgeInsetsGeometry margin;

  const DepletionCheckerCard({
    super.key,
    required this.depletions,
    this.margin = EdgeInsets.zero,
  });

  _CardState get _state {
    if (depletions.isEmpty) return _CardState.empty;
    final anyUncovered = depletions.any(
      (d) => d.coverageLevel == CoverageLevel.none,
    );
    final anyPartial = depletions.any(
      (d) => d.coverageLevel == CoverageLevel.partial,
    );
    if (!anyUncovered && !anyPartial) return _CardState.allCovered;
    if (!anyUncovered) return _CardState.partial;
    return _CardState.noneOrMixed;
  }

  ({
    Color border,
    Color bg,
    Color fg,
    IconData icon,
    String title,
    String subtitle,
  })
  _chrome() {
    switch (_state) {
      case _CardState.allCovered:
        return (
          border: AppTheme.severitySafe.withValues(alpha: 0.32),
          bg: AppTheme.severitySafe.withValues(alpha: 0.04),
          fg: AppTheme.severitySafe,
          icon: Icons.check_circle_outline_rounded,
          title: "You're covered",
          subtitle:
              'Your stack already addresses the nutrients your medications can lower over time.',
        );
      case _CardState.partial:
        return (
          border: AppTheme.severityInformational.withValues(alpha: 0.32),
          bg: AppTheme.severityInformational.withValues(alpha: 0.04),
          fg: AppTheme.severityInformational,
          icon: Icons.info_outline_rounded,
          title: 'A couple of things worth knowing',
          subtitle:
              'Some nutrients your medications can lower over time are partly covered — here are gentle suggestions.',
        );
      case _CardState.noneOrMixed:
        return (
          border: AppTheme.severityInformational.withValues(alpha: 0.35),
          bg: AppTheme.severityInformational.withValues(alpha: 0.05),
          fg: AppTheme.severityInformational,
          icon: Icons.info_outline_rounded,
          title: 'Things worth knowing about your medications',
          subtitle:
              'Some medications can lower certain nutrients gradually over time — here are a few to keep in mind.',
        );
      case _CardState.empty:
        return (
          border: Colors.transparent,
          bg: Colors.transparent,
          fg: Colors.transparent,
          icon: Icons.info_outline,
          title: '',
          subtitle: '',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (depletions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chrome = _chrome();

    return Padding(
      padding: margin,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          side: BorderSide(color: chrome.border),
        ),
        color: chrome.bg,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(chrome.icon, size: 20, color: chrome.fg),
                  const SizedBox(width: AppTheme.space8),
                  Expanded(
                    child: Text(
                      chrome.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: chrome.fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.space4),
              Text(
                chrome.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.space12),
              ...depletions.map((dep) => _DepletionItem(depletion: dep)),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CardState { allCovered, partial, noneOrMixed, empty }

// ---------------------------------------------------------------------------
// Per-depletion item. Renders differently based on coverage level:
//   adequate → green check, acknowledgement copy, collapsed "monitoring
//              tip + learn more" at the bottom
//   partial  → slate check, "you're taking some — consider more" copy
//   none     → soft caution, authored alert_body + monitoring tip
// ---------------------------------------------------------------------------

class _DepletionItem extends StatefulWidget {
  final DepletionMatch depletion;
  const _DepletionItem({required this.depletion});

  @override
  State<_DepletionItem> createState() => _DepletionItemState();
}

class _DepletionItemState extends State<_DepletionItem> {
  bool _expanded = false;

  String _fallbackAlertBody() {
    final d = widget.depletion;
    if (d.clinicalImpact != null && d.clinicalImpact!.isNotEmpty) {
      return d.clinicalImpact!;
    }
    if (d.recommendation.isNotEmpty) return d.recommendation;
    return 'Your medication may gradually affect this nutrient over time.';
  }

  String _fallbackHeadline() {
    final d = widget.depletion;
    return 'Your medication may affect ${d.nutrientName.isEmpty ? "a nutrient" : d.nutrientName} over time';
  }

  String _fallbackAck() {
    final d = widget.depletion;
    final n = d.nutrientName.isEmpty ? 'this nutrient' : d.nutrientName;
    return "You're already taking $n — helpful while on ${d.drugDisplayName}.";
  }

  String _fallbackPartial() {
    final d = widget.depletion;
    final n = d.nutrientName.isEmpty ? 'this nutrient' : d.nutrientName;
    return "You're taking some $n — your medication may warrant a higher dose over time. Worth a quick conversation with your doctor.";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = widget.depletion;

    final (icon, iconColor, primaryCopy, isValidation) = _renderSignals();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space8),
      child: PGCard(
        variant: PGCardVariant.recessed,
        padding: const EdgeInsets.all(AppTheme.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: AppTheme.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.alertHeadline ?? _fallbackHeadline(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppTheme.space2),
                      Text(
                        _subtitleForCoverage(d),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppTheme.space6),
                      Text(
                        primaryCopy,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.86),
                          fontStyle: isValidation
                              ? FontStyle.normal
                              : FontStyle.normal,
                        ),
                      ),
                      if (d.monitoringTipShort != null &&
                          d.monitoringTipShort!.isNotEmpty) ...[
                        const SizedBox(height: AppTheme.space6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lightbulb_outline_rounded,
                              size: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppTheme.space4),
                            Expanded(
                              child: Text(
                                d.monitoringTipShort!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (_hasExpandableDetail()) ...[
              const SizedBox(height: AppTheme.space4),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? 'Show less' : 'Why this happens',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded) _DetailSection(depletion: d),
            ],
          ],
        ),
      ),
    );
  }

  (IconData, Color, String, bool) _renderSignals() {
    final d = widget.depletion;
    switch (d.coverageLevel) {
      case CoverageLevel.adequate:
        return (
          Icons.check_circle_rounded,
          AppTheme.severitySafe,
          d.acknowledgementNote ?? _fallbackAck(),
          true,
        );
      case CoverageLevel.partial:
        return (
          Icons.check_circle_outline_rounded,
          AppTheme.severityInformational,
          _fallbackPartial(),
          false,
        );
      case CoverageLevel.none:
        return (
          Icons.info_outline_rounded,
          AppTheme.severityInformational,
          d.alertBody ?? _fallbackAlertBody(),
          false,
        );
    }
  }

  String _subtitleForCoverage(DepletionMatch d) {
    final drugShort = d.drugDisplayName.isEmpty
        ? 'your medication'
        : d.drugDisplayName;
    final onset = d.onsetTimeline?.toLowerCase();
    final onsetCue = switch (onset) {
      'years' => 'long-term',
      'months' => 'with regular use',
      'weeks' => 'over weeks',
      _ => null,
    };
    if (onsetCue != null) {
      return '$drugShort • $onsetCue';
    }
    return drugShort;
  }

  bool _hasExpandableDetail() {
    final d = widget.depletion;
    return (d.mechanism.isNotEmpty) ||
        (d.clinicalImpact != null && d.clinicalImpact!.isNotEmpty) ||
        (d.recommendation.isNotEmpty) ||
        d.sourceUrls.isNotEmpty;
  }
}

class _DetailSection extends StatelessWidget {
  final DepletionMatch depletion;
  const _DetailSection({required this.depletion});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = depletion;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.clinicalImpact != null && d.clinicalImpact!.isNotEmpty) ...[
            _labelled(theme, 'What can happen', d.clinicalImpact!),
            const SizedBox(height: AppTheme.space8),
          ],
          if (d.foodSourcesShort != null && d.foodSourcesShort!.isNotEmpty) ...[
            _labelled(theme, 'From food', d.foodSourcesShort!),
            const SizedBox(height: AppTheme.space8),
          ],
          if (d.mechanism.isNotEmpty) ...[
            _labelled(theme, 'Why', d.mechanism),
            const SizedBox(height: AppTheme.space8),
          ],
          if (d.recommendation.isNotEmpty) ...[
            _labelled(theme, 'Clinical guidance', d.recommendation),
            const SizedBox(height: AppTheme.space8),
          ],
          if (d.sourceUrls.isNotEmpty) _SourcesRow(urls: d.sourceUrls),
        ],
      ),
    );
  }

  Widget _labelled(ThemeData theme, String label, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: AppTheme.space2),
        Text(
          body,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _SourcesRow extends StatelessWidget {
  final List<String> urls;
  const _SourcesRow({required this.urls});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: urls.take(3).map((url) {
        return InkWell(
          onTap: () {
            final uri = Uri.tryParse(url);
            if (uri == null) return;
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
          },
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              border: Border.all(color: scheme.outlineVariant, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.open_in_new_rounded,
                  size: 11,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTheme.space4),
                Text(
                  'Source',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
