import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';

/// Conditional banner based on mapped_coverage:
/// - < 0.3: Red-tinted warning — limited data, use with caution.
/// - < 0.5: Orange-tinted — some ingredients could not be fully verified.
/// - >= 0.5: Not shown (returns empty SizedBox).
class UnknownIngredientBanner extends StatelessWidget {
  final double mappedCoverage;

  const UnknownIngredientBanner({super.key, required this.mappedCoverage});

  @override
  Widget build(BuildContext context) {
    if (mappedCoverage >= 0.5) return const SizedBox.shrink();

    final isLowCoverage = mappedCoverage < 0.3;
    final color = isLowCoverage ? AppColors.red : AppColors.orange;
    final icon = isLowCoverage
        ? Icons.warning_amber_rounded
        : Icons.info_outline;
    final message = isLowCoverage
        ? 'Limited data available. Use with caution.'
        : 'Some ingredients could not be fully verified.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
