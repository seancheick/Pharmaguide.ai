import 'package:flutter/animation.dart';

/// v2 motion tokens — durations + easings mirroring the website's ladder.
///
/// **Performance contract:**
/// - No nested `BackdropFilter` — one blur layer per viewport section.
/// - Never animate `blur radius` (full-layer repaint).
/// - Gradients stay static.
/// - All motion must remain interruptible.
abstract final class V2Motion {
  // Durations — six-tier ladder.
  static const instant = Duration(milliseconds: 100);
  static const fast = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 420);
  static const slower = Duration(milliseconds: 640);
  static const slowest = Duration(milliseconds: 960);

  // Curves — mirrored from the website's cubic-beziers.
  static const smooth = Cubic(0.65, 0.0, 0.35, 1.0);
  static const emphasized = Cubic(0.32, 0.72, 0.0, 1.0);
  static const decelerate = Cubic(0.0, 0.0, 0.2, 1.0);

  /// **Reserved for celebrations only.** Never on clinical surfaces.
  static const spring = Cubic(0.34, 1.56, 0.64, 1.0);
}
