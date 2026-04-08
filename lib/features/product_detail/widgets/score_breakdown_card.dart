import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';

/// Displays the four scoring section bars for a product.
/// Each section shows label, score/max, and a colored progress bar.
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
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Score Breakdown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 16),
            _SectionBar(
              label: 'Ingredient Quality',
              score: ingredientQuality,
              max: 25,
              color: AppColors.scoreExcellent,
            ),
            const SizedBox(height: 12),
            _SectionBar(
              label: 'Safety & Purity',
              score: safetyPurity,
              max: 30,
              color: AppColors.scoreGood,
            ),
            const SizedBox(height: 12),
            _SectionBar(
              label: 'Evidence & Research',
              score: evidenceResearch,
              max: 20,
              color: AppColors.scoreFair,
            ),
            const SizedBox(height: 12),
            _SectionBar(
              label: 'Brand Trust',
              score: brandTrust,
              max: 5,
              color: AppColors.scoreBelowAvg,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionBar extends StatelessWidget {
  final String label;
  final double? score;
  final int max;
  final Color color;

  const _SectionBar({
    required this.label,
    required this.score,
    required this.max,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final value = score ?? 0.0;
    final fraction = (value / max).clamp(0.0, 1.0);
    final scoreText = score != null ? '${value.toStringAsFixed(1)}/$max' : '--/$max';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              scoreText,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
