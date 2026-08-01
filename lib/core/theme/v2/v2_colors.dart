import 'package:flutter/material.dart';

/// v2 color tokens — warm palette mirroring the PharmaGuide website.
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

  // Dark-mode M3 surface tonal ladder. Each stop sits ~5 luminance points
  // above bgDark — matches Apple's systemGray6→5→4 spacing for layered
  // depth perception, but tinted cool blue-grey to harmonize with the
  // accent rather than feel iOS-neutral.
  static const surfaceContainerLowDark = Color(0xFF13161A);
  static const surfaceContainerHighDark = Color(0xFF1B1F22);
  static const surfaceContainerHighestDark = Color(0xFF22272A);

  // Light-mode highest-elevation surface — neutral-warm offwhite,
  // distinct from `bg` and `surface` so M3 tonal layering works.
  static const surfaceContainerLow = Color(0xFFF4F1EA);
  static const surfaceContainerHighest = Color(0xFFEFEDE8);

  // Scanner-overlay gradient stops. Sit OVER the camera feed (or its
  // mock), distinct from `bgDark` because the chrome wants a darker
  // floor than the v2 dark-mode page.
  static const cameraOverlayTop = Color(0xFF0E1011);
  static const cameraOverlayBottom = Color(0xFF1B1F22);

  // Severity tiers — 5 levels, muted intentionally.
  // NEVER brighten these. The website's reds are muted on purpose.
  static const contraindicated = Color(0xFF9F2929);
  static const contraindicatedTint = Color(0x1A9F2929);
  // These three are darker than the original brand ramp so small clinical
  // labels clear WCAG AA on the lightest elevated surface. Hue and saturation
  // stay intact (drift <=0.3 degrees / 0.3 points); only lightness moves. The
  // full ramp is locked by v2_palette_contrast_test.dart.
  //
  // `avoid` and `monitor` moved a little — dE 4.9 and 4.1, just past the ~2.3
  // just-noticeable threshold. `caution` did NOT: #AD7A24 -> #8A611D is
  // **dE 14.0**, lightness 55.0 -> 44.3. A mid amber became a distinctly
  // darker olive-amber, and it bought the contrast it needed (3.21:1 ->
  // 4.71:1 as small text). Legibility wins on a clinical surface, but the
  // change is plainly visible, so:
  //
  //   THE LIGHT-MODE `caution` NO LONGER MATCHES THE WEBSITE.
  //
  // That divergence is deliberate and unresolved — either the site follows
  // this value or someone accepts two ambers. Do not "restore" the old hex
  // to close the gap; it fails AA and the contrast test will reject it.
  static const avoid = Color(0xFFAA4E2B);
  static const avoidTint = Color(0x1AAA4E2B);
  static const caution = Color(0xFF8A611D);
  static const cautionTint = Color(0x1A8A611D);
  static const monitor = Color(0xFF78683B);
  static const monitorTint = Color(0x1A78683B);
  static const safe = Color(0xFF3F6250);
  static const safeTint = Color(0x1A3F6250);

  // Dark-mode severity tiers.
  //
  // Derived from the light tiers by holding hue and saturation constant and
  // raising ONLY lightness, by the minimum needed to clear 4.5:1. That honours
  // "never brighten these" as far as legibility allows: the light values are
  // unreadable on a dark surface — `contraindicated` measures 2.38:1 and `safe`
  // 2.59:1, both below even the lenient 3:1 large-text floor — and an illegible
  // severity colour is a safety problem, not a style preference.
  //
  // Measured against the LIGHTEST dark surface (`surfaceContainerHighestDark`,
  // #22272A), not `surfaceDark`. A ramp tuned only to the darkest surface
  // passes there and fails on every elevated card — which is where severity
  // pills and badges actually render.
  //
  // Quoted ratios are the worst case across all four dark surfaces, asserted in
  // test/core/theme/v2_palette_contrast_test.dart.
  static const contraindicatedDark = Color(0xFFD96E6E); // 4.60:1
  static const contraindicatedTintDark = Color(0x1FD96E6E);
  static const avoidDark = Color(0xFFD37552); // 4.62:1
  static const avoidTintDark = Color(0x1FD37552);
  static const cautionDark = Color(0xFFBB8427); // 4.63:1
  static const cautionTintDark = Color(0x1FBB8427);
  static const monitorDark = Color(0xFFA28D50); // 4.64:1
  static const monitorTintDark = Color(0x1FA28D50);
  static const safeDark = Color(0xFF639A7D); // 4.63:1
  static const safeTintDark = Color(0x1F639A7D);
}
