import 'package:flutter/material.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';

/// Canonical score-to-color mapping. Thresholds match the verdict system:
///   RECOMMENDED 85-100, GOOD 70-84, MODERATE 55-69,
///   REVIEW 40-54, below 40 poor.
///
/// All consumers MUST use this single function to avoid threshold drift.
Color scoreColor(double? score) {
  if (score == null) return AppColors.textSecondary;
  if (score >= 85) return AppColors.scoreExceptional;
  if (score >= 70) return AppColors.scoreExcellent;
  if (score >= 55) return AppColors.scoreGood;
  if (score >= 40) return AppColors.scoreFair;
  if (score >= 25) return AppColors.scoreBelowAvg;
  return AppColors.scoreLow;
}
