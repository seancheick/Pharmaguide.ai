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

  /// Success — added to stack, low-stakes confirm. Single light pulse.
  /// Decorative; suppressed under reduce-motion. For the high-value
  /// "completion" pattern (Apple Pay "paid", scan-finished-and-safe)
  /// use [successPattern] instead.
  static Future<void> success([BuildContext? context]) {
    if (_shouldSuppressDecorative(context)) return Future<void>.value();
    return HapticFeedback.lightImpact();
  }

  /// **Apple Pay-style success pattern** — di-DUP (light → 80ms →
  /// medium). The chained pattern Apple uses for high-value completions
  /// (Wallet payment success, Health goal hit, Photos save). Reserve
  /// for genuinely-completing events; a regular [success] suffices for
  /// run-of-the-mill confirmations.
  ///
  /// Decorative; suppressed under reduce-motion. Flutter's stable
  /// `HapticFeedback` API doesn't expose `notificationFeedback`, so this
  /// is the closest reproduction of the system di-DUP pattern using
  /// chained impacts. Tactile match is very close on iOS; on Android
  /// the second pulse may render slightly louder than iOS's softer
  /// follow-tap.
  static Future<void> successPattern([BuildContext? context]) async {
    if (_shouldSuppressDecorative(context)) return;
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.mediumImpact();
  }

  /// Warning — caution/monitor severity, mild safety flag. **Always
  /// fires** (safety-critical), even under reduce-motion.
  static Future<void> warning() => HapticFeedback.mediumImpact();

  /// Danger — avoid/contraindicated severity, blocking decision.
  /// **Always fires** (safety-critical), even under reduce-motion.
  static Future<void> danger() => HapticFeedback.heavyImpact();

  /// **Notification-error pattern** — di-da-DUP (medium → 60ms →
  /// medium → 60ms → heavy). Match for the iOS system error sound
  /// (Wallet rejection, Photos delete-failure). Use when an action
  /// has been actively prevented from completing — stronger and more
  /// distinct than [danger] alone. **Always fires** (safety-critical).
  static Future<void> errorPattern() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.heavyImpact();
  }

  /// Error — failed network call, invalid input. **Always fires**.
  /// For severity-tier errors prefer [errorPattern] which produces the
  /// recognizable system di-da-DUP cadence.
  static Future<void> error() => HapticFeedback.vibrate();

  /// Map a [Severity] to the appropriate haptic intensity. Use when a
  /// severity badge first appears on screen (e.g. interaction warning
  /// card mounting) to give the user a tactile signal before they read.
  ///
  /// Safe severities are decorative (suppressed under reduce-motion);
  /// caution/avoid/contraindicated are safety-critical and always fire.
  static Future<void> forSeverity(Severity severity, [BuildContext? context]) {
    switch (severity) {
      case Severity.contraindicated:
        // Strongest pattern for the strict no-go tier — di-da-DUP error.
        return errorPattern();
      case Severity.avoid:
        return danger();
      case Severity.caution:
      case Severity.monitor:
        return warning();
      case Severity.informational:
      case Severity.safe:
        // Informational and safe tiers are non-alarming — light single
        // tap. Callers wanting the Apple Pay completion pattern (e.g.
        // a verdict-flash on a successful scan) should reach for
        // [successPattern] or [forVerdict] directly.
        return success(context);
    }
  }

  /// Map a product **verdict string** (RECOMMENDED / GOOD / MODERATE /
  /// REVIEW / UNSAFE / BLOCKED / NOT_SCORED) to the appropriate haptic
  /// pattern for a scan-result verdict-flash event. Distinct from
  /// [forSeverity] because verdicts are *outcome* signals (the user
  /// completed an action and is about to see the result) where
  /// successful outcomes deserve a stronger celebratory pattern than
  /// a single light tap.
  ///
  /// Mapping:
  /// - RECOMMENDED, GOOD → [successPattern] (Apple Pay-style di-DUP)
  /// - MODERATE, REVIEW  → [warning] (medium)
  /// - UNSAFE            → [danger] (heavy)
  /// - BLOCKED           → [errorPattern] (di-da-DUP error)
  /// - NOT_SCORED        → [success] (light tap — outcome is "we
  ///                       found the product but cannot score it")
  /// - unknown / null    → no haptic
  static Future<void> forVerdict(String? verdict, [BuildContext? context]) {
    final v = (verdict ?? '').trim().toUpperCase();
    switch (v) {
      case 'RECOMMENDED':
      case 'GOOD':
        return successPattern(context);
      case 'MODERATE':
      case 'REVIEW':
        return warning();
      case 'UNSAFE':
        return danger();
      case 'BLOCKED':
        return errorPattern();
      case 'NOT_SCORED':
        return success(context);
      default:
        return Future<void>.value();
    }
  }
}
