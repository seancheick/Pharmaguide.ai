// PGDepletionCard — Medication & Nutrient Monitor surface (B1.1 rewrite).
//
// States what the user's stack SUPPLIES for medication-related nutrient
// relationships — it never authors a coverage verdict ("covered"/"adequate")
// and never implies a measured deficiency or physiological sufficiency. Copy is
// generated from explicit relationship_type × supply_state templates
// (medNutrientBodyCopy); the relationship kind is surfaced per row
// (medNutrientRelationshipLabel) so a functional antagonism or monitoring note
// is never presented as a depletion. Affirmation copy (acknowledgement_note)
// is no longer rendered.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:url_launcher/url_launcher.dart';

class PGDepletionCard extends StatelessWidget {
  final List<DepletionMatch> depletions;
  final EdgeInsetsGeometry margin;

  const PGDepletionCard({
    super.key,
    required this.depletions,
    this.margin = EdgeInsets.zero,
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
            const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: V2Colors.monitor,
                ),
                SizedBox(width: V2Spacing.space8),
                PGEyebrow('Medication & nutrients', color: V2Colors.monitor),
              ],
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Nutrients to monitor',
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              'Some medications are associated with changes in nutrient '
              'status or function. Your supplement stack shows intake—'
              'not your blood level or nutrient status.',
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
            const SizedBox(height: V2Spacing.space12),
            for (final dep in depletions) _DepletionRow(dep: dep),
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
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          border: Border.all(color: V2Colors.outline),
          boxShadow: V2Shadows.sm,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(padding: const EdgeInsets.only(left: 4), child: child),
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(color: V2Colors.monitor),
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
            const Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: V2Colors.monitor,
                ),
                SizedBox(width: V2Spacing.space8),
                PGEyebrow('Medication & nutrients', color: V2Colors.monitor),
              ],
            ),
            const SizedBox(height: V2Spacing.space8),
            Text(
              'Check unavailable',
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              "We couldn't load the medication & nutrient checks right "
              "now. This is not an all-clear — please try again later.",
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
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

  String _bodyCopy() {
    final d = widget.dep;
    num? compAmt;
    String? compUnit;
    if (d.adequacyThresholdMcg != null) {
      compAmt = d.adequacyThresholdMcg;
      compUnit = 'mcg';
    } else if (d.adequacyThresholdMg != null) {
      compAmt = d.adequacyThresholdMg;
      compUnit = 'mg';
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
      comparisonAmount: compAmt,
      comparisonUnit: compUnit,
    );
  }

  String? _onsetCue() {
    final onset = widget.dep.onsetTimeline?.toLowerCase();
    return switch (onset) {
      'years' => 'long-term',
      'months' => 'with regular use',
      'weeks' => 'over weeks',
      _ => null,
    };
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
    final nutrientTitle = d.nutrientName.isEmpty
        ? 'This nutrient'
        : d.nutrientName;
    final subject = d.drugDisplayName.isEmpty
        ? 'your medication'
        : d.drugDisplayName;
    final onset = _onsetCue();
    final subjectLine = onset == null ? subject : '$subject • $onset';

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
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: V2Colors.monitor,
                ),
                const SizedBox(width: V2Spacing.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PGEyebrow(
                        medNutrientRelationshipLabel(d.depletionType),
                        color: V2Colors.fgMuted,
                      ),
                      const SizedBox(height: V2Spacing.space4),
                      Text(
                        nutrientTitle,
                        style: V2Typography.bodyMedium(color: V2Colors.fg),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subjectLine,
                        style: V2Typography.caption(color: V2Colors.fgMuted),
                      ),
                      const SizedBox(height: V2Spacing.space8),
                      Text(
                        _bodyCopy(),
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
