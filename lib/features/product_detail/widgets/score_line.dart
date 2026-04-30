// Compact text-based score line — replaces the score-ring widget on
// the hero card.
//
// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T10
// (the spec example):
//
//   ● 90/100 Exceptional
//   High-quality ingredients, strong evidence, no major safety concerns
//
// Sean's call: the score ring was eating ~120pt of vertical real
// estate on the hero. Yuka-style text rendering reads at a glance and
// frees that space for the actual product info. T11 will swap the
// ring out of the header and drop this widget in.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

class ScoreLine extends StatelessWidget {
  /// Product score on the 0–100 scale. Out-of-range inputs clamp
  /// gracefully via [tierForScore] (≥100 → Exceptional, <0 → Poor).
  final int score;

  /// Optional override for the tier description. Almost always you
  /// want the locked copy from `ScoreTierMeta.description`; this
  /// escape hatch exists so a future sprint can replace the
  /// description with a per-product blurb without re-architecting
  /// the widget.
  final String? descriptionOverride;

  const ScoreLine({super.key, required this.score, this.descriptionOverride});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tier = tierForScore(score);
    // Display the score AS GIVEN even if out of range — the tier
    // is clamped (so the color/label is sane), but a "105/100" UI
    // would be a clear data-quality signal worth surfacing.
    final displayScore = score;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ─── Score line: ● 90/100 Exceptional ────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Tier dot — bold visual signal. 10pt diameter reads at a
            // glance without crowding the typography.
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: tier.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppTheme.space8),
            // Score numeric + tier label — kept as separate Text widgets
            // so `find.text('Exceptional')` matches in widget tests.
            // (A single Text.rich with TextSpan children renders to
            // one Text whose data is the concatenation, which
            // find.text won't match against the bare label.)
            Text(
              '$displayScore/100',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: AppTheme.space8),
            Text(
              tier.label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: tier.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // ─── Description: muted, soft-wraps — no ellipsis cap ────
        Text(
          descriptionOverride ?? tier.description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
