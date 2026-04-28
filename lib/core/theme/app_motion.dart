import 'package:flutter/material.dart';

/// Motion tokens — durations and curves.
///
/// Use these instead of magic numbers so the whole app breathes at the same
/// rhythm. A premium app feels smooth because every animation agrees on
/// timing, not because any single animation is fancy.
///
/// ### Scale
/// - **fast** (150ms)   — state flips, chip toggles, icon rotations
/// - **medium** (240ms) — card expand/collapse, sheet open, focus ring
/// - **slow** (320ms)   — page transitions, hero moments
/// - **emphasized** (420ms) — onboarding reveals, scan-success celebration
abstract final class AppMotion {
  static const instant = Duration.zero;
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 320);
  static const emphasized = Duration(milliseconds: 420);

  /// Default curve — natural deceleration, good for most state changes.
  static const standard = Curves.easeOutCubic;

  /// Emphasized out — MD3 spec, slightly more dramatic.
  static const emphasizedCurve = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Decelerate — for content entering the screen.
  static const decelerate = Cubic(0.0, 0.0, 0.2, 1.0);

  /// Accelerate — for content leaving the screen.
  static const accelerate = Cubic(0.4, 0.0, 1.0, 1.0);

  /// Subtle spring — small overshoot, premium but never bouncy.
  /// Reserve for **state flips and toggles** where a touch of overshoot
  /// adds personality (chip on/off, switch toggle, success badge mount).
  ///
  /// **Do NOT use this for press-release** on cards or buttons. Apple's
  /// iOS press-up has a near-zero rebound — using a spring with overshoot
  /// here reads as toy-like rather than premium. Prefer
  /// [gentleRelease] for press-up transitions.
  static const spring = Cubic(0.175, 0.885, 0.32, 1.15);

  /// Press-release curve — pure ease-out, no overshoot. The
  /// iOS button-press rebound profile: fast at the start (the finger
  /// just lifted), gracefully decelerating to rest with no oscillation.
  /// Use for the "press-up" half of any tactile widget (PGPressable,
  /// custom button rebounds).
  static const gentleRelease = Curves.easeOutCubic;
}

/// Elevation tokens — shadow sets for layered depth.
///
/// Prefer surface-tone layering ([ColorScheme.surfaceContainer*]) over shadow
/// whenever possible. Only add shadow when something is genuinely floating:
/// modal sheets, floating action buttons, dragged items.
abstract final class AppElevation {
  /// No shadow.
  static const List<BoxShadow> none = <BoxShadow>[];

  /// Level 1 — subtle card lift.
  static const List<BoxShadow> low = [
    BoxShadow(
      color: Color(0x0A000000), // 4% ink
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Level 2 — elevated / floating buttons.
  static const List<BoxShadow> medium = [
    BoxShadow(
      color: Color(0x0F000000), // 6% ink
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x05000000), // 2% ink
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];

  /// Level 3 — modal / floating sheets.
  static const List<BoxShadow> high = [
    BoxShadow(
      color: Color(0x14000000), // 8% ink
      blurRadius: 32,
      offset: Offset(0, 12),
      spreadRadius: -4,
    ),
    BoxShadow(
      color: Color(0x0A000000), // 4% ink
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
}
