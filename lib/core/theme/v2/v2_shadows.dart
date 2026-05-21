import 'package:flutter/material.dart';

/// v2 shadow tokens — 3-tier soft-layered.
///
/// **Performance contract:** Shadows must be cached. Wrap animated subtrees
/// that read these in `RepaintBoundary` to avoid full repaint on rebuild.
/// Never combine more than two shadow layers; never animate shadow values.
abstract final class V2Shadows {
  static const List<BoxShadow> none = <BoxShadow>[];

  /// Tier 1 — subtle card lift.
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x0A181A1B), blurRadius: 6, offset: Offset(0, 1)),
  ];

  /// Tier 2 — elevated card / floating element.
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x0D181A1B), blurRadius: 12, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x05181A1B), blurRadius: 4, offset: Offset(0, 1)),
  ];

  /// Tier 3 — modal / floating sheet / hero card.
  static const List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x14181A1B),
      blurRadius: 32,
      offset: Offset(0, 12),
      spreadRadius: -6,
    ),
    BoxShadow(color: Color(0x08181A1B), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// Accent glow — for primary CTA hover/press state only.
  static const List<BoxShadow> accentGlow = [
    BoxShadow(
      color: Color(0x33183B3F),
      blurRadius: 20,
      offset: Offset(0, 8),
      spreadRadius: -4,
    ),
  ];
}
