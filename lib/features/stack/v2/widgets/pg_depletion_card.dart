// PGDepletionCard — Phase 11.7L.C.
//
// V2 depletion coverage surface. Same three-state machine
// (all_covered / partial / none_or_mixed), same data shape,
// same calm-not-alarming tone. The fallback copy is preserved verbatim —
// these messages were tuned in the Sprint 16 Path C calibration and
// remain Sean-approved.
//
// What's different visually:
//
//   * Cream `V2Colors.surface` card with a severity-tinted left
//     stripe (4px) that signals the coverage state without
//     dominating the surface.
//   * Header: mono-caps eyebrow + Newsreader serif title + body
//     subtitle (Geist Sans muted).
//   * Per-depletion rows render as nested cream tiles with the
//     coverage icon at the leading edge and an expandable "Why this
//     happens" disclosure.
//   * Source URL chips use accent-tinted pills.
//
// Behavior + content preserve the production card contract.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:url_launcher/url_launcher.dart';

enum _CardState { allCovered, partial, noneOrMixed, empty }

class PGDepletionCard extends StatelessWidget {
  final List<DepletionMatch> depletions;
  final EdgeInsetsGeometry margin;

  const PGDepletionCard({
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
    Color stripe,
    Color iconColor,
    IconData icon,
    String eyebrow,
    String title,
    String subtitle,
  })
  _chrome() {
    switch (_state) {
      case _CardState.allCovered:
        // Sean 2026-05-16: "You're covered" felt a touch casual for
        // a clinical card. "Coverage looks good" matches the calm-
        // clinical tone of the rest of the depletion surfaces.
        return (
          stripe: V2Colors.safe,
          iconColor: V2Colors.safe,
          icon: Icons.check_circle_outline_rounded,
          eyebrow: 'Depletion check',
          title: 'Coverage looks good',
          subtitle:
              'Your stack already addresses the nutrients your '
              'medications can lower over time.',
        );
      case _CardState.partial:
        return (
          stripe: V2Colors.monitor,
          iconColor: V2Colors.monitor,
          icon: Icons.info_outline_rounded,
          eyebrow: 'Depletion check',
          title: 'A couple of things worth knowing',
          subtitle:
              'Some nutrients your medications can lower over time are '
              'partly covered — here are gentle suggestions.',
        );
      case _CardState.noneOrMixed:
        return (
          stripe: V2Colors.monitor,
          iconColor: V2Colors.monitor,
          icon: Icons.info_outline_rounded,
          eyebrow: 'Depletion check',
          title: 'Things worth knowing about your medications',
          subtitle:
              'Some medications can lower certain nutrients gradually '
              'over time — here are a few to keep in mind.',
        );
      case _CardState.empty:
        return (
          stripe: Colors.transparent,
          iconColor: Colors.transparent,
          icon: Icons.info_outline,
          eyebrow: '',
          title: '',
          subtitle: '',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (depletions.isEmpty) return const SizedBox.shrink();
    final chrome = _chrome();

    return Padding(
      padding: margin,
      child: Container(
        decoration: BoxDecoration(
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: V2Colors.outline),
          boxShadow: V2Shadows.sm,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: chrome.stripe),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(V2Spacing.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(chrome.icon, size: 16, color: chrome.iconColor),
                        const SizedBox(width: V2Spacing.space8),
                        PGEyebrow(chrome.eyebrow, color: chrome.iconColor),
                      ],
                    ),
                    const SizedBox(height: V2Spacing.space8),
                    Text(
                      chrome.title,
                      style: V2Typography.titleSm(color: V2Colors.fg),
                    ),
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      chrome.subtitle,
                      style: V2Typography.bodySm(color: V2Colors.fgMuted),
                    ),
                    const SizedBox(height: V2Spacing.space12),
                    for (final dep in depletions) _DepletionRow(dep: dep),
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

// =============================================================================
// Per-depletion row — stateful for the "Why this happens" disclosure.
// =============================================================================

class _DepletionRow extends StatefulWidget {
  final DepletionMatch dep;
  const _DepletionRow({required this.dep});

  @override
  State<_DepletionRow> createState() => _DepletionRowState();
}

class _DepletionRowState extends State<_DepletionRow> {
  bool _expanded = false;

  String _fallbackAlertBody() {
    final d = widget.dep;
    if (d.clinicalImpact != null && d.clinicalImpact!.isNotEmpty) {
      return d.clinicalImpact!;
    }
    if (d.recommendation.isNotEmpty) return d.recommendation;
    return 'Your medication may gradually affect this nutrient over time.';
  }

  String _fallbackHeadline() {
    final d = widget.dep;
    final n = d.nutrientName.isEmpty ? 'a nutrient' : d.nutrientName;
    return 'Your medication may affect $n over time';
  }

  String _fallbackAck() {
    final d = widget.dep;
    final n = d.nutrientName.isEmpty ? 'this nutrient' : d.nutrientName;
    return "You're already taking $n — helpful while on ${d.drugDisplayName}.";
  }

  String _fallbackPartial() {
    final d = widget.dep;
    final n = d.nutrientName.isEmpty ? 'this nutrient' : d.nutrientName;
    return "You're taking some $n — your medication may warrant a "
        'higher dose over time. Worth a quick conversation with your doctor.';
  }

  (IconData, Color, String) _renderSignals() {
    final d = widget.dep;
    switch (d.coverageLevel) {
      case CoverageLevel.adequate:
        return (
          Icons.check_circle_rounded,
          V2Colors.safe,
          d.acknowledgementNote ?? _fallbackAck(),
        );
      case CoverageLevel.partial:
        return (
          Icons.check_circle_outline_rounded,
          V2Colors.monitor,
          _fallbackPartial(),
        );
      case CoverageLevel.none:
        return (
          Icons.info_outline_rounded,
          V2Colors.monitor,
          d.alertBody ?? _fallbackAlertBody(),
        );
    }
  }

  String _subtitleForCoverage(DepletionMatch d) {
    final drugShort = d.drugDisplayName.isEmpty
        ? 'your medication'
        : d.drugDisplayName;
    final onset = d.onsetTimeline?.toLowerCase();
    final cue = switch (onset) {
      'years' => 'long-term',
      'months' => 'with regular use',
      'weeks' => 'over weeks',
      _ => null,
    };
    return cue == null ? drugShort : '$drugShort • $cue';
  }

  bool _hasExpandableDetail() {
    final d = widget.dep;
    return d.mechanism.isNotEmpty ||
        (d.clinicalImpact != null && d.clinicalImpact!.isNotEmpty) ||
        d.recommendation.isNotEmpty ||
        d.sourceUrls.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dep;
    final (icon, iconColor, primaryCopy) = _renderSignals();

    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Container(
        padding: const EdgeInsets.all(V2Spacing.space12),
        decoration: BoxDecoration(
          color: V2Colors.bg,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: V2Colors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: V2Spacing.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.alertHeadline ?? _fallbackHeadline(),
                        style: V2Typography.bodyMedium(color: V2Colors.fg),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitleForCoverage(d),
                        style: V2Typography.caption(color: V2Colors.fgMuted),
                      ),
                      const SizedBox(height: V2Spacing.space8),
                      Text(
                        primaryCopy,
                        style: V2Typography.bodySm(color: V2Colors.fg),
                      ),
                      if (d.monitoringTipShort != null &&
                          d.monitoringTipShort!.isNotEmpty) ...[
                        const SizedBox(height: V2Spacing.space8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.lightbulb_outline_rounded,
                              size: 14,
                              color: V2Colors.fgMuted,
                            ),
                            const SizedBox(width: V2Spacing.space4),
                            Expanded(
                              child: Text(
                                d.monitoringTipShort!,
                                style: V2Typography.caption(
                                  color: V2Colors.fgMuted,
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
              const SizedBox(height: V2Spacing.space8),
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? 'Show less' : 'Why this happens',
                        style: V2Typography.label(color: V2Colors.accent),
                      ),
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 16,
                        color: V2Colors.accent,
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded) _DetailSection(dep: d),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Expandable detail — labeled paragraphs + source chips.
// =============================================================================

class _DetailSection extends StatelessWidget {
  final DepletionMatch dep;
  const _DetailSection({required this.dep});

  @override
  Widget build(BuildContext context) {
    final d = dep;
    return Container(
      margin: const EdgeInsets.only(top: V2Spacing.space8),
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        color: V2Colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.clinicalImpact != null && d.clinicalImpact!.isNotEmpty) ...[
            _labelled('What can happen', d.clinicalImpact!),
            const SizedBox(height: V2Spacing.space8),
          ],
          if (d.foodSourcesShort != null && d.foodSourcesShort!.isNotEmpty) ...[
            _labelled('From food', d.foodSourcesShort!),
            const SizedBox(height: V2Spacing.space8),
          ],
          if (d.mechanism.isNotEmpty) ...[
            _labelled('Why', d.mechanism),
            const SizedBox(height: V2Spacing.space8),
          ],
          if (d.recommendation.isNotEmpty) ...[
            _labelled('Clinical guidance', d.recommendation),
            const SizedBox(height: V2Spacing.space8),
          ],
          if (d.sourceUrls.isNotEmpty) _SourcesRow(urls: d.sourceUrls),
        ],
      ),
    );
  }

  Widget _labelled(String label, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PGEyebrow(label, color: V2Colors.fgMuted),
        const SizedBox(height: V2Spacing.space4),
        Text(body, style: V2Typography.bodySm(color: V2Colors.fg)),
      ],
    );
  }
}

class _SourcesRow extends StatelessWidget {
  final List<String> urls;
  const _SourcesRow({required this.urls});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: V2Spacing.space8,
      runSpacing: V2Spacing.space8,
      children: urls.take(3).map((url) {
        return InkWell(
          onTap: () {
            final uri = Uri.tryParse(url);
            if (uri == null) return;
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
          },
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space12,
              vertical: V2Spacing.space4,
            ),
            decoration: BoxDecoration(
              color: V2Colors.surface,
              borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
              border: Border.all(color: V2Colors.outline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 11,
                  color: V2Colors.fgMuted,
                ),
                const SizedBox(width: V2Spacing.space4),
                Text(
                  'Source',
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
