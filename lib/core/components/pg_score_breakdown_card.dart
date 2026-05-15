import 'package:flutter/material.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One pillar's data as the v2 widget consumes it.
///
/// Mirrors what production's `_ExpandableSectionBar` reads — name,
/// micro-explanation, raw score on a pillar-specific scale (max), an
/// optional sub-breakdown map for tap-to-expand explanation, and badges
/// for callouts like "Third-party tested" / "Trusted manufacturer".
class PGPillar {
  /// Display name, e.g. "Ingredient Quality" or "Transparency & Verification".
  final String label;

  /// 1-line context shown beneath the bar. Production examples:
  /// "Form, dosage, and bioavailability", "Clinical support behind
  /// ingredients", "Label clarity and independent testing".
  final String? microExplanation;

  /// Raw pillar score on its own scale (e.g. 22/25 for Ingredient Quality,
  /// 4/5 for Transparency & Verification). Null when no data.
  final double? score;

  /// Pillar's max raw score. Production: 25 / 30 / 20 / 5 for the four
  /// pillars. Drives the bar fill (`score / max`) AND the "22/25" label.
  final int max;

  /// Optional 1-line callouts rendered to the right of the bar
  /// (e.g. "Third-party tested" with verified icon).
  final List<PGPillarBadge> badges;

  /// Tap → opens production's expand-to-explain panel. Null = inert.
  final VoidCallback? onTap;

  const PGPillar({
    required this.label,
    required this.max,
    this.score,
    this.microExplanation,
    this.badges = const [],
    this.onTap,
  });
}

class PGPillarBadge {
  final IconData icon;
  final String label;
  final Color color;
  const PGPillarBadge({
    required this.icon,
    required this.label,
    required this.color,
  });
}

/// v2 mirror of `ScoreBreakdownCard`
/// (lib/features/product_detail/widgets/score_breakdown_card.dart:35).
///
/// **Same structure preserved verbatim:**
/// - 4 pillar bars (Ingredient Quality / Safety & Purity / Evidence &
///   Research / Transparency & Verification), each as a horizontal
///   bar + raw score + microExplanation + optional badges
/// - Coverage line at the bottom (production `_CoverageLine`) — 3-tier
///   confidence indicator based on `mappedCoverage` ratio
/// - Each pillar is tappable to open the explain panel (caller wires
///   the production handler)
///
/// **What changes in v2:**
/// - Surface: cream + outline + sm shadow (production uses PGCard.elevated)
/// - Typography: Geist Sans 500 for pillar labels (production w700)
/// - Bar color: driven by the production [scoreFromPillar] → ScoreTier
///   color map — same palette as PGScoreLine, no new tiers
/// - Bar: 6pt height, rounded, tinted track + tier-colored fill
class PGScoreBreakdownCard extends StatelessWidget {
  /// 4 pillars in production order. Caller composes from the pipeline
  /// blob; sequence matters because users scan top-to-bottom.
  final List<PGPillar> pillars;

  /// 0..1 — drives the coverage line at the bottom. Null hides the line.
  final double? mappedCoverage;

  const PGScoreBreakdownCard({
    super.key,
    required this.pillars,
    this.mappedCoverage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < pillars.length; i++) ...[
            if (i > 0) const SizedBox(height: V2Spacing.space16),
            _PGPillarRow(pillar: pillars[i]),
          ],
          if (mappedCoverage != null) ...[
            const SizedBox(height: V2Spacing.space16),
            const Divider(
              color: V2Colors.outline,
              height: 1,
              thickness: 0.5,
            ),
            const SizedBox(height: V2Spacing.space12),
            _PGCoverageLine(coverage: mappedCoverage!),
          ],
        ],
      ),
    );
  }
}

class _PGPillarRow extends StatelessWidget {
  final PGPillar pillar;
  const _PGPillarRow({required this.pillar});

  /// Map pillar raw fraction to a v2 tier color. Reuses the existing
  /// [tierForScore] on a normalized 0–100 scale so colors stay in sync
  /// with PGScoreLine and the rest of v2.
  Color _toneFor(double? rawScore, int max) {
    if (rawScore == null) return V2Colors.fgSubtle;
    final normalized = (rawScore / max * 100).round();
    return tierForScore(normalized).color;
  }

  @override
  Widget build(BuildContext context) {
    final score = pillar.score;
    final max = pillar.max;
    final hasScore = score != null;
    final fill = hasScore ? (score / max).clamp(0.0, 1.0) : 0.0;
    final tone = _toneFor(score, max);

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pillar.label,
                  style: V2Typography.bodyMedium(color: V2Colors.fg),
                ),
              ),
              if (hasScore)
                Text(
                  '${_fmt(score)}/$max',
                  style: V2Typography.monoData(color: V2Colors.fgMuted),
                )
              else
                Text(
                  'No data',
                  style: V2Typography.caption(color: V2Colors.fgSubtle),
                ),
            ],
          ),
          const SizedBox(height: V2Spacing.space8),
          ClipRRect(
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  // Track — outline alpha for a quiet base.
                  Container(color: V2Colors.outline.withValues(alpha: 0.45)),
                  // Fill.
                  FractionallySizedBox(
                    widthFactor: fill,
                    child: Container(color: tone),
                  ),
                ],
              ),
            ),
          ),
          if (pillar.microExplanation != null) ...[
            const SizedBox(height: V2Spacing.space8),
            Text(
              pillar.microExplanation!,
              style: V2Typography.caption(color: V2Colors.fgMuted),
            ),
          ],
          if (pillar.badges.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final b in pillar.badges) _PillarBadgeChip(badge: b),
              ],
            ),
          ],
        ],
      ),
    );

    if (pillar.onTap == null) return row;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: pillar.onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: row,
      ),
    );
  }

  String _fmt(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(1);
  }
}

class _PillarBadgeChip extends StatelessWidget {
  final PGPillarBadge badge;
  const _PillarBadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 12, color: badge.color),
          const SizedBox(width: 4),
          Text(
            badge.label,
            style: V2Typography.caption(color: badge.color).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// v2 mirror of `_CoverageLine` (score_breakdown_card.dart:619). Same
/// 3-tier thresholds: ≥0.7 high-confidence (scoreExcellent), ≥0.3
/// partial (scoreFair), else limited (insufficientData). Same locked
/// descriptor copy.
class _PGCoverageLine extends StatelessWidget {
  final double coverage;
  const _PGCoverageLine({required this.coverage});

  ({Color tone, String label}) _tierFor(double c) {
    if (c >= 0.7) {
      return (
        tone: AppTheme.scoreExcellent,
        label: 'Most ingredients in our database — high-confidence score',
      );
    }
    if (c >= 0.3) {
      return (
        tone: AppTheme.scoreFair,
        label: 'Some ingredients aren\'t in our database — partial coverage',
      );
    }
    return (
      tone: AppTheme.insufficientData,
      label: 'Limited data — only part of this product is in our database',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tier = _tierFor(coverage);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: tier.tone, shape: BoxShape.circle),
        ),
        const SizedBox(width: V2Spacing.space8),
        Expanded(
          child: Text(
            tier.label,
            style: V2Typography.caption(color: V2Colors.fgMuted),
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}
