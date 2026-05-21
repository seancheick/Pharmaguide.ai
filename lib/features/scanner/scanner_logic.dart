// Pure helpers for the scanner screen. Extracted so the verdict-to-color
// policy can be unit-tested without pumping a full widget tree.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';

/// Return the flash color associated with a scanned product's verdict
/// string. Case-insensitive; null and unrecognized values stay neutral.
///
/// Policy:
///   SAFE / GOOD / RECOMMENDED   → safe
///   CAUTION / REVIEW / MODERATE → caution
///   POOR                        → avoid
///   BLOCKED / UNSAFE            → contraindicated
///   NOT_SCORED / NUTRITION_ONLY → neutral
///   null / unknown              → neutral (not green)
Color verdictFlashColor(String? verdict) {
  switch (verdict?.trim().toUpperCase()) {
    case 'RECOMMENDED':
    case 'SAFE':
    case 'GOOD':
      return V2Colors.safe;
    case 'CAUTION':
    case 'MODERATE':
    case 'REVIEW':
      return V2Colors.caution;
    case 'POOR':
      return V2Colors.avoid;
    case 'BLOCKED':
    case 'UNSAFE':
      return V2Colors.contraindicated;
    case 'NOT_SCORED':
    case 'NUTRITION_ONLY':
    default:
      return V2Colors.fgSubtle;
  }
}
