// PGDepletionCard — Medication & Nutrient Monitor surface (B1.1 rewrite).
//
// States what the user's stack SUPPLIES for medication-related nutrient
// relationships — it never authors a coverage verdict ("covered"/"adequate")
// and never implies a measured deficiency or physiological sufficiency. Copy is
// combines factual stack-supply copy with clinician-reviewed artifact context;
// the relationship kind is surfaced per row
// (medNutrientRelationshipLabel) so a functional antagonism or monitoring note
// is never presented as a depletion. Affirmation copy (acknowledgement_note)
// is no longer rendered.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/depletion_watch.dart';
import 'package:url_launcher/url_launcher.dart';

class PGDepletionCard extends StatelessWidget {
  final List<DepletionMatch> depletions;
  final EdgeInsetsGeometry margin;

  /// Curated watch thresholds that have elapsed, keyed by depletion entry id.
  ///
  /// Empty by default and empty in practice until a clinical reviewer authors a
  /// `watch_threshold_days`, so the card renders exactly as before unless the
  /// pipeline says otherwise.
  final Map<String, DepletionWatchStatus> watchStatuses;

  const PGDepletionCard({
    super.key,
    required this.depletions,
    this.margin = EdgeInsets.zero,
    this.watchStatuses = const {},
  });

  @override
  Widget build(BuildContext context) {
    if (depletions.isEmpty) return const SizedBox.shrink();

    return _MedicationNutrientFrame(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.all(V2Spacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: context.v2.monitor,
                ),
                const SizedBox(width: V2Spacing.space8),
                PGEyebrow('Personalized review', color: context.v2.monitor),
              ],
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Medication & nutrients',
              style: V2Typography.titleSm(color: context.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              "Supplement amounts don't show blood nutrient levels.",
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space12),
            for (final dep in depletions)
              _DepletionRow(dep: dep, watch: watchStatuses[dep.depletionId]),
          ],
        ),
      ),
    );
  }
}

class _MedicationNutrientFrame extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  final Widget child;

  const _MedicationNutrientFrame({required this.margin, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        decoration: BoxDecoration(
          color: context.v2.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: context.v2.outline),
          boxShadow: V2Shadows.sm,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(padding: const EdgeInsets.only(left: 4), child: child),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(color: context.v2.monitor),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the medication–nutrient artifact could not be activated (B1.2
/// App-1). This is an EXPLICIT unavailable state — never a clean "no depletions"
/// state, which would be a false all-clear.
class PGDepletionUnavailableCard extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  const PGDepletionUnavailableCard({super.key, this.margin = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return _MedicationNutrientFrame(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.all(V2Spacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: context.v2.monitor,
                ),
                const SizedBox(width: V2Spacing.space8),
                PGEyebrow('Medication & nutrients', color: context.v2.monitor),
              ],
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Check unavailable',
              style: V2Typography.titleSm(color: context.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              "We couldn't load the medication & nutrient checks right "
              "now. This is not an all-clear — please try again later.",
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Per-depletion row — long clinical context opens in a scrollable sheet so
// reviewing one relationship never makes the parent Stack page grow in place.
// =============================================================================

class _DepletionRow extends StatelessWidget {
  final DepletionMatch dep;

  /// Non-null only when a reviewer-authored threshold exists for this entry.
  final DepletionWatchStatus? watch;

  const _DepletionRow({required this.dep, this.watch});

  /// True once the curated threshold has elapsed. The row raises the emphasis
  /// of the tip it already shows rather than adding a second copy of it.
  bool get _isDue => watch?.isDue ?? false;

  /// Device fact only: how long this medication has been tracked *here*, never
  /// a claim about how long the person has taken it. Their prescription may
  /// predate the app by years.
  String _trackedForLine() {
    final months = watch!.trackedMonths;
    if (months < 24) return 'Tracked here for about $months months';
    final years = months ~/ 12;
    return 'Tracked here for about $years years';
  }

  String _summaryCopy() {
    final d = dep;
    final reviewed = d.alertBody?.trim() ?? '';
    if (d.depletionType == 'functional_antagonism' && reviewed.isNotEmpty) {
      return reviewed;
    }
    return medNutrientBodyCopy(
      relationshipType: d.depletionType,
      nutrient: d.nutrientName,
      subject: d.drugDisplayName,
      supplyState: medNutrientSupplyStateFrom(
        d.coverageLevel,
        hasAmount: d.detectedAmount != null,
      ),
      detectedAmount: d.detectedAmount,
      detectedUnit: d.detectedUnit,
    );
  }

  bool _hasExpandableDetail() {
    final d = dep;
    return d.mechanism.isNotEmpty ||
        (d.clinicalImpact != null && d.clinicalImpact!.isNotEmpty) ||
        d.recommendation.isNotEmpty ||
        d.sourceUrls.isNotEmpty;
  }

  void _showDetails(BuildContext context) {
    unawaited(
      PGModal.bottomSheet<void>(
        context: context,
        builder: (_) => _MedicationNutrientDetailsSheet(dep: dep),
      ),
    );
  }

  String _affordanceLabel() => dep.depletionType == 'functional_antagonism'
      ? 'Why this matters'
      : 'What to monitor';

  @override
  Widget build(BuildContext context) {
    final d = dep;
    final nutrientTitle = d.nutrientName.isEmpty
        ? 'This nutrient'
        : d.nutrientName;
    final reviewedHeadline = d.alertHeadline?.trim() ?? '';
    final rowTitle = reviewedHeadline.isEmpty
        ? nutrientTitle
        : reviewedHeadline;
    final hasDetails = _hasExpandableDetail();
    final affordance = _affordanceLabel();
    final semanticsParts = <String>[
      rowTitle,
      medNutrientRelationshipLabel(d.depletionType),
      _summaryCopy(),
      if (_isDue) _trackedForLine(),
      if (hasDetails) affordance,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: V2Spacing.space8),
      child: Semantics(
        button: hasDetails,
        excludeSemantics: true,
        label: semanticsParts.join('. '),
        child: Material(
          color: context.v2.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            side: BorderSide(color: context.v2.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: hasDetails ? () => _showDetails(context) : null,
            child: Padding(
              padding: const EdgeInsets.all(V2Spacing.space12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: context.v2.monitor,
                  ),
                  const SizedBox(width: V2Spacing.space8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PGEyebrow(
                          medNutrientRelationshipLabel(d.depletionType),
                          color: context.v2.fgMuted,
                        ),
                        const SizedBox(height: V2Spacing.space4),
                        Text(
                          rowTitle,
                          style: V2Typography.bodyMedium(color: context.v2.fg),
                        ),
                        const SizedBox(height: V2Spacing.space8),
                        Text(
                          _summaryCopy(),
                          style: V2Typography.bodySm(color: context.v2.fg),
                        ),
                        if (_isDue) ...[
                          const SizedBox(height: V2Spacing.space8),
                          Semantics(
                            // The clock icon is decorative; the sentence carries
                            // the meaning, so emphasis is never colour-only.
                            label: _trackedForLine(),
                            excludeSemantics: true,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 14,
                                  color: context.v2.monitor,
                                ),
                                const SizedBox(width: V2Spacing.space4),
                                Expanded(
                                  child: Text(
                                    _trackedForLine(),
                                    style: V2Typography.caption(
                                      color: context.v2.monitor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (hasDetails) ...[
                          const SizedBox(height: V2Spacing.space8),
                          SizedBox(
                            height: 44,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  affordance,
                                  style: V2Typography.label(
                                    color: context.v2.accent,
                                  ),
                                ),
                                const SizedBox(width: V2Spacing.space4),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: context.v2.accent,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Scrollable detail sheet — labeled paragraphs + source chips.
// =============================================================================

class _MedicationNutrientDetailsSheet extends StatelessWidget {
  final DepletionMatch dep;
  const _MedicationNutrientDetailsSheet({required this.dep});

  @override
  Widget build(BuildContext context) {
    final rawDrug = dep.drugDisplayName.trim();
    final drug = rawDrug.isEmpty
        ? 'Your medication'
        : rawDrug.split(' (').first.trim();
    final nutrient = dep.nutrientName.trim().isEmpty
        ? 'This nutrient'
        : dep.nutrientName;

    return Semantics(
      label: 'Medication and nutrient details for $drug and $nutrient',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space24,
          V2Spacing.space8,
          V2Spacing.space24,
          V2Spacing.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PGEyebrow(
              medNutrientRelationshipLabel(dep.depletionType),
              color: context.v2.monitor,
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              '$drug & $nutrient',
              style: V2Typography.titleSm(color: context.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [_DetailSection(dep: dep)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        color: context.v2.surfaceHighest,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.clinicalImpact != null && d.clinicalImpact!.isNotEmpty) ...[
            _labelled(context, 'What can happen', d.clinicalImpact!),
            const SizedBox(height: V2Spacing.space8),
          ],
          if ((d.alertBody?.trim().isNotEmpty ?? false) ||
              d.mechanism.isNotEmpty) ...[
            _labelled(
              context,
              'Why',
              d.alertBody?.trim().isNotEmpty ?? false
                  ? d.alertBody!.trim()
                  : d.mechanism,
            ),
            const SizedBox(height: V2Spacing.space8),
          ],
          if (d.recommendation.isNotEmpty) ...[
            _labelled(context, 'What to do', d.recommendation),
            const SizedBox(height: V2Spacing.space8),
          ],
          if (d.sourceUrls.isNotEmpty) _SourcesRow(dep: d),
        ],
      ),
    );
  }

  Widget _labelled(BuildContext context, String label, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PGEyebrow(label, color: context.v2.fgMuted),
        const SizedBox(height: V2Spacing.space4),
        Text(body, style: V2Typography.bodySm(color: context.v2.fg)),
      ],
    );
  }
}

class _SourcesRow extends StatelessWidget {
  final DepletionMatch dep;
  const _SourcesRow({required this.dep});

  @override
  Widget build(BuildContext context) {
    final sources = dep.sources.isNotEmpty
        ? dep.sources
        : [
            for (final url in dep.sourceUrls)
              DepletionSource(sourceType: '', label: 'Source', url: url),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PGEyebrow('Sources', color: context.v2.fgMuted),
        const SizedBox(height: V2Spacing.space8),
        for (final source in sources.take(3)) ...[
          InkWell(
            onTap: () {
              final uri = Uri.tryParse(source.url);
              if (uri == null) return;
              unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
            },
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.space12,
                  vertical: V2Spacing.space4,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 11,
                      color: context.v2.fgMuted,
                    ),
                    const SizedBox(width: V2Spacing.space4),
                    Expanded(
                      child: Text(
                        source.label,
                        style: V2Typography.caption(color: context.v2.fgMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (source != sources.take(3).last)
            const SizedBox(height: V2Spacing.space4),
        ],
      ],
    );
  }
}
