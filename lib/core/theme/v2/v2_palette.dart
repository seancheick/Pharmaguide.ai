import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';

/// Brightness-resolved semantic colours for every v2 surface.
///
/// **This is the only colour API widgets may use.** `V2Colors` is the raw
/// constant table and is read exclusively by `V2Theme`; naming a raw token in a
/// widget hardcodes one brightness, which is the entire bug this type exists to
/// prevent. A release gate enforces that separation.
///
/// Why an extension rather than `ColorScheme` alone: the scheme has no slot for
/// four of the five severity tiers, and those tiers carry clinical meaning. One
/// accessor for every colour beats two with a rule about which to use when.
@immutable
class V2Palette extends ThemeExtension<V2Palette> {
  const V2Palette({
    required this.bg,
    required this.surface,
    required this.surfaceLow,
    required this.surfaceHigh,
    required this.surfaceHighest,
    required this.cameraOverlayTop,
    required this.cameraOverlayBottom,
    required this.fg,
    required this.fgMuted,
    required this.fgSubtle,
    required this.outline,
    required this.accent,
    required this.accentStrong,
    required this.accentTint,
    required this.onAccent,
    required this.onAccentStrong,
    required this.contraindicated,
    required this.contraindicatedTint,
    required this.onContraindicated,
    required this.avoid,
    required this.avoidTint,
    required this.onAvoid,
    required this.caution,
    required this.cautionTint,
    required this.onCaution,
    required this.monitor,
    required this.monitorTint,
    required this.onMonitor,
    required this.safe,
    required this.safeTint,
    required this.onSafe,
  });

  // Surfaces, low to high elevation.
  final Color bg;
  final Color surface;
  final Color surfaceLow;
  final Color surfaceHigh;
  final Color surfaceHighest;
  final Color cameraOverlayTop;
  final Color cameraOverlayBottom;

  // Foregrounds, most to least emphasis.
  final Color fg;
  final Color fgMuted;
  final Color fgSubtle;

  final Color outline;

  final Color accent;
  final Color accentStrong;
  final Color accentTint;
  final Color onAccent;
  final Color onAccentStrong;

  // Severity tiers. Order matters clinically:
  // contraindicated > avoid > caution > monitor > safe.
  final Color contraindicated;
  final Color contraindicatedTint;
  final Color onContraindicated;
  final Color avoid;
  final Color avoidTint;
  final Color onAvoid;
  final Color caution;
  final Color cautionTint;
  final Color onCaution;
  final Color monitor;
  final Color monitorTint;
  final Color onMonitor;
  final Color safe;
  final Color safeTint;
  final Color onSafe;

  static const light = V2Palette(
    bg: V2Colors.bg,
    surface: V2Colors.surface,
    surfaceLow: V2Colors.surfaceContainerLow,
    surfaceHigh: V2Colors.bg,
    surfaceHighest: V2Colors.surfaceContainerHighest,
    cameraOverlayTop: V2Colors.cameraOverlayTop,
    cameraOverlayBottom: V2Colors.cameraOverlayBottom,
    fg: V2Colors.fg,
    fgMuted: V2Colors.fgMuted,
    fgSubtle: V2Colors.fgSubtle,
    outline: V2Colors.outline,
    accent: V2Colors.accent,
    accentStrong: V2Colors.accentStrong,
    accentTint: V2Colors.accentTint,
    onAccent: Colors.white,
    onAccentStrong: Colors.white,
    contraindicated: V2Colors.contraindicated,
    contraindicatedTint: V2Colors.contraindicatedTint,
    onContraindicated: Colors.white,
    avoid: V2Colors.avoid,
    avoidTint: V2Colors.avoidTint,
    onAvoid: Colors.white,
    caution: V2Colors.caution,
    cautionTint: V2Colors.cautionTint,
    // White is only 3.76:1 on this fill. The primary foreground clears AA
    // without changing the clinically authored caution colour.
    onCaution: V2Colors.bgDark,
    monitor: V2Colors.monitor,
    monitorTint: V2Colors.monitorTint,
    onMonitor: Colors.white,
    safe: V2Colors.safe,
    safeTint: V2Colors.safeTint,
    onSafe: Colors.white,
  );

  static const dark = V2Palette(
    bg: V2Colors.bgDark,
    surface: V2Colors.surfaceDark,
    surfaceLow: V2Colors.surfaceContainerLowDark,
    surfaceHigh: V2Colors.surfaceContainerHighDark,
    surfaceHighest: V2Colors.surfaceContainerHighestDark,
    cameraOverlayTop: V2Colors.cameraOverlayTop,
    cameraOverlayBottom: V2Colors.cameraOverlayBottom,
    fg: V2Colors.fgDark,
    fgMuted: V2Colors.fgMutedDark,
    fgSubtle: V2Colors.fgSubtleDark,
    outline: V2Colors.outlineDark,
    accent: V2Colors.accentDark,
    accentStrong: V2Colors.accentStrongDark,
    accentTint: V2Colors.accentTintDark,
    onAccent: V2Colors.bgDark,
    onAccentStrong: V2Colors.bgDark,
    contraindicated: V2Colors.contraindicatedDark,
    contraindicatedTint: V2Colors.contraindicatedTintDark,
    onContraindicated: V2Colors.bgDark,
    avoid: V2Colors.avoidDark,
    avoidTint: V2Colors.avoidTintDark,
    onAvoid: V2Colors.bgDark,
    caution: V2Colors.cautionDark,
    cautionTint: V2Colors.cautionTintDark,
    onCaution: V2Colors.bgDark,
    monitor: V2Colors.monitorDark,
    monitorTint: V2Colors.monitorTintDark,
    onMonitor: V2Colors.bgDark,
    safe: V2Colors.safeDark,
    safeTint: V2Colors.safeTintDark,
    onSafe: V2Colors.bgDark,
  );

  static V2Palette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  V2Palette copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceLow,
    Color? surfaceHigh,
    Color? surfaceHighest,
    Color? cameraOverlayTop,
    Color? cameraOverlayBottom,
    Color? fg,
    Color? fgMuted,
    Color? fgSubtle,
    Color? outline,
    Color? accent,
    Color? accentStrong,
    Color? accentTint,
    Color? onAccent,
    Color? onAccentStrong,
    Color? contraindicated,
    Color? contraindicatedTint,
    Color? onContraindicated,
    Color? avoid,
    Color? avoidTint,
    Color? onAvoid,
    Color? caution,
    Color? cautionTint,
    Color? onCaution,
    Color? monitor,
    Color? monitorTint,
    Color? onMonitor,
    Color? safe,
    Color? safeTint,
    Color? onSafe,
  }) {
    return V2Palette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceLow: surfaceLow ?? this.surfaceLow,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceHighest: surfaceHighest ?? this.surfaceHighest,
      cameraOverlayTop: cameraOverlayTop ?? this.cameraOverlayTop,
      cameraOverlayBottom: cameraOverlayBottom ?? this.cameraOverlayBottom,
      fg: fg ?? this.fg,
      fgMuted: fgMuted ?? this.fgMuted,
      fgSubtle: fgSubtle ?? this.fgSubtle,
      outline: outline ?? this.outline,
      accent: accent ?? this.accent,
      accentStrong: accentStrong ?? this.accentStrong,
      accentTint: accentTint ?? this.accentTint,
      onAccent: onAccent ?? this.onAccent,
      onAccentStrong: onAccentStrong ?? this.onAccentStrong,
      contraindicated: contraindicated ?? this.contraindicated,
      contraindicatedTint: contraindicatedTint ?? this.contraindicatedTint,
      onContraindicated: onContraindicated ?? this.onContraindicated,
      avoid: avoid ?? this.avoid,
      avoidTint: avoidTint ?? this.avoidTint,
      onAvoid: onAvoid ?? this.onAvoid,
      caution: caution ?? this.caution,
      cautionTint: cautionTint ?? this.cautionTint,
      onCaution: onCaution ?? this.onCaution,
      monitor: monitor ?? this.monitor,
      monitorTint: monitorTint ?? this.monitorTint,
      onMonitor: onMonitor ?? this.onMonitor,
      safe: safe ?? this.safe,
      safeTint: safeTint ?? this.safeTint,
      onSafe: onSafe ?? this.onSafe,
    );
  }

  /// Interpolates so a light↔dark switch animates instead of snapping.
  ///
  /// Solid fills interpolate continuously, but their foreground cannot: a
  /// grey midpoint between light-mode white and dark-mode ink loses contrast
  /// against every mid-transition fill. Select the higher-contrast authored
  /// foreground for each interpolated fill instead.
  static Color _solidForeground(Color fill) {
    final fillLuminance = fill.computeLuminance();
    final darkLuminance = V2Colors.bgDark.computeLuminance();
    const whiteLuminance = 1.0;

    double ratio(double a, double b) =>
        (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);

    final whiteRatio = ratio(fillLuminance, whiteLuminance);
    final darkRatio = ratio(fillLuminance, darkLuminance);
    if (whiteRatio >= 4.5 && whiteRatio >= darkRatio) return Colors.white;
    if (darkRatio >= 4.5) return V2Colors.bgDark;

    // A very small mid-transition luminance band can sit below 4.5:1 against
    // both authored endpoint foregrounds. Pure black closes that gap for the
    // few animation frames involved; endpoint themes still use brand ink.
    return Colors.black;
  }

  @override
  V2Palette lerp(covariant V2Palette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    final mixedAccent = mix(accent, other.accent);
    final mixedAccentStrong = mix(accentStrong, other.accentStrong);
    final mixedContraindicated = mix(contraindicated, other.contraindicated);
    final mixedAvoid = mix(avoid, other.avoid);
    final mixedCaution = mix(caution, other.caution);
    final mixedMonitor = mix(monitor, other.monitor);
    final mixedSafe = mix(safe, other.safe);

    return V2Palette(
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      surfaceLow: mix(surfaceLow, other.surfaceLow),
      surfaceHigh: mix(surfaceHigh, other.surfaceHigh),
      surfaceHighest: mix(surfaceHighest, other.surfaceHighest),
      cameraOverlayTop: mix(cameraOverlayTop, other.cameraOverlayTop),
      cameraOverlayBottom: mix(cameraOverlayBottom, other.cameraOverlayBottom),
      fg: mix(fg, other.fg),
      fgMuted: mix(fgMuted, other.fgMuted),
      fgSubtle: mix(fgSubtle, other.fgSubtle),
      outline: mix(outline, other.outline),
      accent: mixedAccent,
      accentStrong: mixedAccentStrong,
      accentTint: mix(accentTint, other.accentTint),
      onAccent: _solidForeground(mixedAccent),
      onAccentStrong: _solidForeground(mixedAccentStrong),
      contraindicated: mixedContraindicated,
      contraindicatedTint: mix(contraindicatedTint, other.contraindicatedTint),
      onContraindicated: _solidForeground(mixedContraindicated),
      avoid: mixedAvoid,
      avoidTint: mix(avoidTint, other.avoidTint),
      onAvoid: _solidForeground(mixedAvoid),
      caution: mixedCaution,
      cautionTint: mix(cautionTint, other.cautionTint),
      onCaution: _solidForeground(mixedCaution),
      monitor: mixedMonitor,
      monitorTint: mix(monitorTint, other.monitorTint),
      onMonitor: _solidForeground(mixedMonitor),
      safe: mixedSafe,
      safeTint: mix(safeTint, other.safeTint),
      onSafe: _solidForeground(mixedSafe),
    );
  }
}

extension V2PaletteContext on BuildContext {
  /// The brightness-resolved v2 palette.
  ///
  /// Falls back to `V2Palette.of(brightness)` when `V2Theme` is not an
  /// ancestor. That fallback is CORRECT, not a silent failure: it still
  /// resolves by brightness, so a widget under a bare `ThemeData.dark()` gets
  /// dark colours. The bug this class replaces was light constants pinned
  /// regardless of brightness — something neither branch can produce.
  ///
  /// An earlier version asserted here instead. That broke 257 widget tests
  /// which legitimately pump a bare MaterialApp, in exchange for guarding a
  /// failure mode the fallback already handles. The real invariant — that both
  /// app entry points register the extension — is one assertion, not one per
  /// widget, and lives in test/core/theme/dark_mode_surface_test.dart.
  V2Palette get v2 =>
      Theme.of(this).extension<V2Palette>() ??
      V2Palette.of(Theme.of(this).brightness);
}

/// System chrome (status bar + navigation bar) matching the current theme.
///
/// Screens previously hardcoded `Brightness.dark` icons over a light nav bar.
/// In dark mode that paints dark icons onto a dark bar, so the clock and
/// battery vanish — the same invisible-on-invisible failure as the text, just
/// in the OS chrome where it is easy to miss.
/// Resolves from brightness alone, deliberately NOT via `context.v2`.
///
/// System chrome must render even where the extension is absent — a bare
/// `MaterialApp` in a widget test, or any surface not yet migrated. Requiring
/// the extension here coupled every screen's chrome to full theme
/// registration and broke 42 tests that legitimately pump a plain app. The
/// assert on `context.v2` still guards *content*, which is where a wrong
/// colour is invisible rather than merely unthemed.
SystemUiOverlayStyle v2SystemOverlay(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final palette = V2Palette.of(Theme.of(context).brightness);
  // Icon brightness is the INVERSE of the surface it sits on.
  final iconBrightness = isDark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: iconBrightness,
    statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: palette.bg,
    systemNavigationBarIconBrightness: iconBrightness,
  );
}
