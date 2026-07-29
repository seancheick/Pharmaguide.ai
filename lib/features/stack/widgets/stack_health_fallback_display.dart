import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';

/// Shared fallback for stack-health surfaces before a diagnosis is available.
///
/// An errored safety provider is neutral and explicit, never green. Home and
/// Stack both consume this helper so one screen cannot present an unavailable
/// analysis as clean while the other hedges.
({Color tone, String label}) stackHealthFallbackDisplay({
  required bool isAnalyzing,
  required bool hasError,
}) {
  if (isAnalyzing) {
    return (tone: V2Colors.safe, label: 'Analyzing');
  }
  if (hasError) {
    return (tone: V2Colors.fgMuted, label: "Couldn't check");
  }
  return (tone: V2Colors.safe, label: 'No data yet');
}

String stackHealthFallbackSummary({
  required bool isAnalyzing,
  required bool hasError,
}) {
  if (isAnalyzing) {
    return 'Reviewing interactions, recall alerts, and nutrient overlap.';
  }
  if (hasError) {
    return 'Some safety checks could not be completed. This is not an '
        'all-clear.';
  }
  return 'Add supplements or medications to review this stack.';
}
