import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/constants/severity.dart';

/// Haptic feedback helper — maps app events to the right iOS/Android
/// impact intensity. Centralized so UX feedback is consistent and we can
/// tune once.
///
/// **Accessibility:** When a [BuildContext] is provided, every helper
/// respects `MediaQueryData.disableAnimations`. Users who enable "reduce
/// motion" in iOS Settings → Accessibility or Android Settings →
/// Accessibility → Remove animations typically also want reduced
/// non-essential haptics (many use this to reduce sensory load). We skip
/// press/success/tap haptics in that case but still fire warning/danger/
/// error because those are safety-critical signals.
abstract final class PGHaptics {
  static bool _shouldSuppressDecorative(BuildContext? context) {
    if (context == null) return false;
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  /// Standard tap feedback — navigation, list item taps. Decorative;
  /// suppressed under reduce-motion.
  static Future<void> tap([BuildContext? context]) {
    if (_shouldSuppressDecorative(context)) return Future<void>.value();
    return HapticFeedback.selectionClick();
  }

  /// Press confirmation — button tap, toggle flip. Decorative; suppressed
  /// under reduce-motion.
  static Future<void> press([BuildContext? context]) {
    if (_shouldSuppressDecorative(context)) return Future<void>.value();
    return HapticFeedback.lightImpact();
  }

  /// Success — added to stack, scan succeeded, safe product. Decorative;
  /// suppressed under reduce-motion.
  static Future<void> success([BuildContext? context]) {
    if (_shouldSuppressDecorative(context)) return Future<void>.value();
    return HapticFeedback.lightImpact();
  }

  /// Warning — caution/monitor severity, mild safety flag. **Always
  /// fires** (safety-critical), even under reduce-motion.
  static Future<void> warning() => HapticFeedback.mediumImpact();

  /// Danger — avoid/contraindicated severity, blocking decision.
  /// **Always fires** (safety-critical), even under reduce-motion.
  static Future<void> danger() => HapticFeedback.heavyImpact();

  /// Error — failed network call, invalid input. **Always fires**.
  static Future<void> error() => HapticFeedback.vibrate();

  /// Map a [Severity] to the appropriate haptic intensity. Use when a
  /// severity badge first appears on screen (e.g. interaction warning
  /// card mounting) to give the user a tactile signal before they read.
  ///
  /// Safe severities are decorative (suppressed under reduce-motion);
  /// caution/avoid/contraindicated are safety-critical and always fire.
  static Future<void> forSeverity(Severity severity,
      [BuildContext? context]) {
    switch (severity) {
      case Severity.contraindicated:
      case Severity.avoid:
        return danger();
      case Severity.caution:
      case Severity.monitor:
        return warning();
      case Severity.informational:
      case Severity.safe:
        // Informational and safe tiers are non-alarming — no haptic.
        return success(context);
    }
  }
}
