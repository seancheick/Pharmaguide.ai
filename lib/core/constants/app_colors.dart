import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Semantic color tokens.
///
/// **In widgets with a BuildContext:** prefer `AppColors.of(context)` which
/// returns a brightness-aware palette (light or dark).
///
/// **Static fields** resolve to light-mode values and are safe for use in
/// const contexts, model classes, or places without a `BuildContext`.
abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Theme-aware resolver (preferred in widgets)
  // ---------------------------------------------------------------------------

  /// Returns a brightness-aware color set for the current theme.
  static ResolvedColors of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? ResolvedColors.dark
        : ResolvedColors.light;
  }

  // ---------------------------------------------------------------------------
  // Static light-mode defaults (backward compat, const-safe)
  // ---------------------------------------------------------------------------
  static const background = AppTheme.lightBackground;
  static const surface = AppTheme.lightSurface;
  static const textPrimary = AppTheme.lightTextPrimary;
  static const textSecondary = Color(0xFF64748B);
  static const border = AppTheme.lightBorder;

  // ---------------------------------------------------------------------------
  // Severity / score colors — identical in both modes (high contrast by design)
  // ---------------------------------------------------------------------------
  static const red = Color(0xFFDC2626);
  static const orange = Color(0xFFF97316);
  static const yellow = Color(0xFFEAB308);
  static const green = Color(0xFF22C55E);

  static const scoreExceptional = Color(0xFF059669);
  static const scoreExcellent = Color(0xFF22C55E);
  static const scoreGood = Color(0xFF84CC16);
  static const scoreFair = Color(0xFFEAB308);
  static const scoreBelowAvg = Color(0xFFF97316);
  static const scoreLow = Color(0xFFEF4444);
  static const scoreVeryPoor = Color(0xFFDC2626);
}

/// Brightness-resolved color set returned by [AppColors.of].
class ResolvedColors {
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;

  const ResolvedColors({
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
  });

  static const light = ResolvedColors(
    background: AppTheme.lightBackground,
    surface: AppTheme.lightSurface,
    textPrimary: AppTheme.lightTextPrimary,
    textSecondary: Color(0xFF64748B),
    border: AppTheme.lightBorder,
  );

  static const dark = ResolvedColors(
    background: AppTheme.darkBackground,
    surface: AppTheme.darkSurface,
    textPrimary: AppTheme.darkTextPrimary,
    textSecondary: AppTheme.darkTextSecondary,
    border: AppTheme.darkBorder,
  );
}
