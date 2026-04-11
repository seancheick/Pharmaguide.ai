import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

/// Score breakdown card — four sub-section bars for a product's base score.
///
/// Uses [PGCard] + dynamic color bands: each bar's color comes from
/// `score/max` ratio, NOT the category. A 5/5 Brand Trust now renders
/// green (exceptional), not orange.
class ScoreBreakdownCard extends StatelessWidget {
  final double? ingredientQuality;
  final double? safetyPurity;
  final double? evidenceResearch;
  final double? brandTrust;

  const ScoreBreakdownCard({
    super.key,
    this.ingredientQuality,
    this.safetyPurity,
    this.evidenceResearch,
    this.brandTrust,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Score breakdown',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.15,
            ),
          ),
          const SizedBox(height: AppTheme.space16),
          _SectionBar(
            label: 'Ingredient quality',
            score: ingredientQuality,
            max: 25,
          ),
          const SizedBox(height: AppTheme.space12),
          _SectionBar(
            label: 'Safety & purity',
            score: safetyPurity,
            max: 30,
          ),
          const SizedBox(height: AppTheme.space12),
          _SectionBar(
            label: 'Evidence & research',
            score: evidenceResearch,
            max: 20,
          ),
          const SizedBox(height: AppTheme.space12),
          _SectionBar(
            label: 'Brand trust',
            score: brandTrust,
            max: 5,
          ),
        ],
      ),
    );
  }
}

class _SectionBar extends StatelessWidget {
  final String label;
  final double? score;
  final int max;

  const _SectionBar({
    required this.label,
    required this.score,
    required this.max,
  });

  /// Same color bands as [PGScoreRing] — percent-of-max thresholds.
  static Color _colorFor(double fraction) {
    if (fraction >= 0.85) return AppTheme.scoreExceptional;
    if (fraction >= 0.70) return AppTheme.scoreExcellent;
    if (fraction >= 0.55) return AppTheme.scoreGood;
    if (fraction >= 0.40) return AppTheme.scoreFair;
    if (fraction >= 0.25) return AppTheme.scoreBelowAvg;
    return AppTheme.scoreLow;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = score ?? 0.0;
    final fraction = (value / max).clamp(0.0, 1.0);
    final color = _colorFor(fraction);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            Text(
              score != null
                  ? '${value.toStringAsFixed(1)}/$max'
                  : '—/$max',
              style: AppTheme.numeric(
                theme.textTheme.labelMedium!.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
