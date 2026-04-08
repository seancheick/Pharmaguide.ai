import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';

/// Shared verdict badge used across search results and product detail.
class VerdictBadge extends StatelessWidget {
  final String verdict;
  const VerdictBadge({super.key, required this.verdict});

  static Color colorFor(String verdict) {
    switch (verdict.toUpperCase()) {
      case 'RECOMMENDED':
        return AppColors.scoreExceptional;
      case 'GOOD':
        return AppColors.scoreExcellent;
      case 'MODERATE':
        return AppColors.scoreBelowAvg;
      case 'REVIEW':
        return AppColors.scoreFair;
      case 'UNSAFE':
      case 'BLOCKED':
        return AppColors.red;
      case 'NOT_SCORED':
        return AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (verdict.isEmpty) return const SizedBox.shrink();
    final color = colorFor(verdict);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        verdict.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
