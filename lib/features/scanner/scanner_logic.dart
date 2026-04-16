// Pure helpers for the scanner screen. Extracted so the verdict-to-color
// policy can be unit-tested without pumping a full widget tree.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Return the flash color associated with a scanned product's verdict
/// string. Case-insensitive; null and unrecognized values fall through
/// to the default green.
///
/// Policy:
///   RECOMMENDED          → scoreExceptional (bright green)
///   GOOD                 → scoreExcellent   (green)
///   REVIEW / MODERATE    → severityCaution  (amber)
///   BLOCKED / UNSAFE     → severityContraindicated (red)
///   null / anything else → scoreExcellent   (green, safe default)
Color verdictFlashColor(String? verdict) {
  switch (verdict?.toUpperCase()) {
    case 'RECOMMENDED':
      return AppTheme.scoreExceptional;
    case 'GOOD':
      return AppTheme.scoreExcellent;
    case 'REVIEW':
    case 'MODERATE':
      return AppTheme.severityCaution;
    case 'BLOCKED':
    case 'UNSAFE':
      return AppTheme.severityContraindicated;
    default:
      return AppTheme.scoreExcellent;
  }
}
