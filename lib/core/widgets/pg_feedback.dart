import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Centralized error / success / info feedback for the entire app.
///
/// Replaces ad-hoc `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))`
/// calls with a consistent API that enforces:
/// - Correct severity coloring (danger / warning / success / info)
/// - Consistent duration (short for success, longer for errors)
/// - Optional undo action with callback
/// - Accessibility: announce via SnackBarBehavior.floating for screen readers
///
/// Usage:
///   PGFeedback.error(context, 'Could not load product.');
///   PGFeedback.success(context, 'Added to stack.', undo: () => restore());
///   PGFeedback.info(context, 'Searching...');
enum PGFeedbackTone { error, warning, success, info }

class PGFeedback {
  PGFeedback._();

  /// Show an error snackbar (red, 4s duration).
  static void error(BuildContext context, String message) {
    _show(context, message, PGFeedbackTone.error);
  }

  /// Show a warning snackbar (amber, 3s duration).
  static void warning(BuildContext context, String message) {
    _show(context, message, PGFeedbackTone.warning);
  }

  /// Show a success snackbar (green, 2s duration). Optional [undo] callback
  /// adds an "Undo" action button with a 5s window.
  static void success(
    BuildContext context,
    String message, {
    VoidCallback? undo,
  }) {
    _show(
      context,
      message,
      PGFeedbackTone.success,
      undo: undo,
      duration: undo != null
          ? const Duration(seconds: 5)
          : const Duration(seconds: 2),
    );
  }

  /// Show an info snackbar (neutral, 2s duration).
  static void info(BuildContext context, String message) {
    _show(context, message, PGFeedbackTone.info);
  }

  static void _show(
    BuildContext context,
    String message,
    PGFeedbackTone tone, {
    VoidCallback? undo,
    Duration? duration,
  }) {
    final scheme = Theme.of(context).colorScheme;

    final Color background;
    final Color foreground;
    final Duration effectiveDuration;

    switch (tone) {
      case PGFeedbackTone.error:
        background = AppTheme.severityAvoid;
        foreground = Colors.white;
        effectiveDuration = duration ?? const Duration(seconds: 4);
      case PGFeedbackTone.warning:
        background = AppTheme.severityCaution;
        foreground = Colors.black87;
        effectiveDuration = duration ?? const Duration(seconds: 3);
      case PGFeedbackTone.success:
        background = AppTheme.severitySafe;
        foreground = Colors.white;
        effectiveDuration = duration ?? const Duration(seconds: 2);
      case PGFeedbackTone.info:
        background = scheme.inverseSurface;
        foreground = scheme.onInverseSurface;
        effectiveDuration = duration ?? const Duration(seconds: 2);
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: foreground)),
          backgroundColor: background,
          behavior: SnackBarBehavior.floating,
          duration: effectiveDuration,
          action: undo != null
              ? SnackBarAction(
                  label: 'Undo',
                  textColor: foreground,
                  onPressed: undo,
                )
              : null,
        ),
      );
  }
}
