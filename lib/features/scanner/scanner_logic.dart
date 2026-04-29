// Pure helpers for the scanner screen. Extracted so the verdict-to-color
// policy can be unit-tested without pumping a full widget tree.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Return the flash color associated with a scanned product's verdict
/// string. Case-insensitive; null and unrecognized values stay neutral.
///
/// Policy:
///   SAFE / legacy GOOD / RECOMMENDED → scoreExcellent / exceptional
///   CAUTION / legacy REVIEW          → severityCaution (amber)
///   POOR / legacy MODERATE           → scoreLow / below average
///   BLOCKED / legacy UNSAFE          → severityContraindicated (red)
///   NOT_SCORED / NUTRITION_ONLY      → insufficientData
///   null / unknown                   → insufficientData (not green)
Color verdictFlashColor(String? verdict) {
  switch (verdict?.trim().toUpperCase()) {
    case 'RECOMMENDED':
      return AppTheme.scoreExceptional;
    case 'SAFE':
    case 'GOOD':
      return AppTheme.scoreExcellent;
    case 'CAUTION':
    case 'MODERATE':
    case 'REVIEW':
      return AppTheme.severityCaution;
    case 'POOR':
      return AppTheme.scoreLow;
    case 'BLOCKED':
    case 'UNSAFE':
      return AppTheme.severityContraindicated;
    case 'NOT_SCORED':
    case 'NUTRITION_ONLY':
    default:
      return AppTheme.insufficientData;
  }
}
