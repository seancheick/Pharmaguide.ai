import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_score_breakdown_card.dart';
import 'package:pharmaguide/core/scoring/v4_pillars.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Compact paired pillar row for the Compare surface.
///
/// One pillar, two products: label on top, then product A's mini bar +
/// score/max beside product B's. Visual language mirrors
/// `PGScoreBreakdownCard`'s pillar bars — same 6pt rounded bar, the
/// shared calm 2-tone palette ([PGScoreBreakdownCard.pillarTone]; pillars
/// are QUALITY signals, never alarm-red), and the shared
/// [PGScoreBreakdownCard.fmtScore] formatter so "17.5/20" renders
/// identically everywhere.
///
/// Each side carries its OWN max ([maxA] / [maxB]) — both blobs may
/// legitimately disagree on a pillar's scale, and rendering B's bar
/// against A's max would distort B's fill.
///
/// Deliberately presentational: no winner highlighting, no comparison
/// judgment — both sides get identical treatment.
class PGComparePillarRow extends StatelessWidget {
  /// Pillar display label, e.g. "Formulation".
  final String label;

  /// Product A's pillar max, e.g. 20.
  final int maxA;

  /// Product B's pillar max — usually equal to [maxA], but B's bar and
  /// "score/max" label always use B's own scale.
  final int maxB;

  /// Product A's raw pillar score. Null renders an empty bar + em dash.
  final double? scoreA;

  /// Product B's raw pillar score. Null renders an empty bar + em dash.
  final double? scoreB;

  const PGComparePillarRow({
    super.key,
    required this.label,
    required this.maxA,
    required this.maxB,
    this.scoreA,
    this.scoreB,
  });

  Widget _side(BuildContext context, double? score, int max) {
    final tone = PGScoreBreakdownCard.pillarTone(score, max, context.v2);
    final fill = (score == null || max <= 0)
        ? 0.0
        : (score / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Container(color: context.v2.outline.withValues(alpha: 0.45)),
                FractionallySizedBox(
                  widthFactor: fill,
                  child: Container(color: tone),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: V2Spacing.space4),
        Text(
          score == null ? '—' : '${PGScoreBreakdownCard.fmtScore(score)}/$max',
          style: V2Typography.monoData(
            color: score == null ? context.v2.fgSubtle : tone,
          ),
        ),
        // Shared presentation status (Strong / Mixed / Limited) beside the
        // score — the SAME statusForPillar thresholds the score card uses, so
        // Compare and the breakdown never disagree. Hidden for a null score,
        // which reads as "no data" (em dash), not "Limited".
        if (score != null) ...[
          const SizedBox(height: 2),
          Text(
            v4PillarStatusLabel(statusForPillar(score, max)),
            style: V2Typography.caption(color: tone),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: V2Typography.bodyMedium(color: context.v2.fg)),
        const SizedBox(height: V2Spacing.space8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _side(context, scoreA, maxA)),
            const SizedBox(width: V2Spacing.space16),
            Expanded(child: _side(context, scoreB, maxB)),
          ],
        ),
      ],
    );
  }
}
