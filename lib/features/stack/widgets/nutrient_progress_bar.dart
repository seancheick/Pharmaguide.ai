// NutrientProgressBar — single-row visualization for one nutrient's
// stack-wide total against RDA and UL benchmarks.
//
// The bar fills against the UL (when present) so a user can see how
// close they are to the ceiling at a glance. When no UL exists (e.g.
// most B vitamins), the bar fills against 200% RDA instead, which is
// the upper end of the "abundant" band.
//
// Colors come from the [NutrientTier] enum via a pure function — no
// context required — so the widget is const-friendly and testable
// without a MaterialApp.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

class NutrientProgressBar extends StatelessWidget {
  const NutrientProgressBar({
    super.key,
    required this.status,
  });

  final NutrientStatus status;

  @override
  Widget build(BuildContext context) {
    final total = status.total;
    final tierColor = tierColorFor(status.tier);
    final fillPct = _fillPercent(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  total.displayName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                _formatAmount(total.totalAmount, total.unit),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fillPct.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(tierColor),
            ),
          ),
          const SizedBox(height: 6),
          _buildSubtitleRow(),
          if (status.warning != null) ...[
            const SizedBox(height: 8),
            _WarningChip(
              text: status.warning!,
              color: tierColor,
            ),
          ],
          if (total.hasUnitConflict) ...[
            const SizedBox(height: 4),
            const Text(
              'Note: this total excludes products reported in a different unit.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Subtitle: "XX% RDA  •  YY% UL" or just one when the other is null.
  Widget _buildSubtitleRow() {
    final parts = <String>[];
    final rda = status.pctOfRda;
    final ul = status.pctOfUl;
    if (rda != null) parts.add('${rda.round()}% RDA');
    if (ul != null) parts.add('${ul.round()}% UL');

    final text = parts.isEmpty ? 'No RDA data' : parts.join('  •  ');

    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: AppColors.textSecondary,
      ),
    );
  }

  /// Choose what the bar fills against. Priority:
  ///   1. % UL, when available (most informative for safety)
  ///   2. % RDA scaled so 200% = full bar
  ///   3. Zero when nothing is known
  double _fillPercent(NutrientStatus status) {
    final ul = status.pctOfUl;
    if (ul != null) return ul / 100.0;
    final rda = status.pctOfRda;
    if (rda != null) return (rda / 200.0).clamp(0.0, 1.0);
    return 0.0;
  }

  static String _formatAmount(double amount, String unit) {
    final rounded = amount >= 10
        ? amount.round().toString()
        : amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 1);
    return unit.isEmpty ? rounded : '$rounded ${unit.toUpperCase()}/day';
  }

  /// Map a tier to its bar color. Pure function so it can be used from
  /// tests and other widgets without re-parameterising. Exposed as a
  /// static helper rather than a private method.
  static Color tierColorFor(NutrientTier tier) {
    switch (tier) {
      case NutrientTier.exceedsUl:
        return AppColors.red;
      case NutrientTier.approachingUl:
        return AppColors.orange;
      case NutrientTier.aboveTypical:
        return AppColors.yellow;
      case NutrientTier.abundant:
        return AppColors.scoreGood;
      case NutrientTier.adequate:
        return AppColors.green;
      case NutrientTier.underFifty:
      case NutrientTier.noRda:
        return AppColors.textSecondary;
    }
  }
}

class _WarningChip extends StatelessWidget {
  const _WarningChip({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
