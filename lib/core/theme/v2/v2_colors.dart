import 'package:flutter/material.dart';

/// v2 color tokens — warm palette mirroring the PharmaGuide website.
///
/// **Do NOT use outside `lib/core/theme/v2/` and `lib/core/components/`**
/// while v2 is experimental. Feature screens still consume `AppTheme`.
abstract final class V2Colors {
  // Light surfaces — warm, never cold.
  static const bg = Color(0xFFFAF9F6);
  static const surface = Color(0xFFFFFFFF);
  static const fg = Color(0xFF181A1B);
  static const fgMuted = Color(0xFF5C5F61);
  static const fgSubtle = Color(0xFF8A8D90);
  static const outline = Color(0x0F181A1B);

  // Dark surfaces.
  static const bgDark = Color(0xFF0E1011);
  static const surfaceDark = Color(0xFF16191A);
  static const fgDark = Color(0xFFE8E6E1);
  static const fgMutedDark = Color(0xFFA8A6A2);
  static const fgSubtleDark = Color(0xFF7A7875);
  static const outlineDark = Color(0x14E8E6E1);

  // Accent — deep clinical teal.
  static const accent = Color(0xFF183B3F);
  static const accentStrong = Color(0xFF246066);
  static const accentTint = Color(0x1A183B3F);
  static const accentDark = Color(0xFF7BB8BD);
  static const accentStrongDark = Color(0xFFA2D3D7);
  static const accentTintDark = Color(0x1A7BB8BD);

  // Severity tiers — 5 levels, muted intentionally.
  // NEVER brighten these. The website's reds are muted on purpose.
  static const contraindicated = Color(0xFF9F2929);
  static const contraindicatedTint = Color(0x1A9F2929);
  static const avoid = Color(0xFFB8542F);
  static const avoidTint = Color(0x1AB8542F);
  static const caution = Color(0xFFAD7A24);
  static const cautionTint = Color(0x1AAD7A24);
  static const monitor = Color(0xFF827140);
  static const monitorTint = Color(0x1A827140);
  static const safe = Color(0xFF3F6250);
  static const safeTint = Color(0x1A3F6250);
}
