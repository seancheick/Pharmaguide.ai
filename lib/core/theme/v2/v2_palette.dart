import 'package:flutter/material.dart';
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
    required this.surfaceHigh,
    required this.surfaceHighest,
    required this.fg,
    required this.fgMuted,
    required this.fgSubtle,
    required this.outline,
    required this.accent,
    required this.accentStrong,
    required this.accentTint,
    required this.contraindicated,
    required this.contraindicatedTint,
    required this.avoid,
    required this.avoidTint,
    required this.caution,
    required this.cautionTint,
    required this.monitor,
    required this.monitorTint,
    required this.safe,
    required this.safeTint,
  });

  // Surfaces, low to high elevation.
  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color surfaceHighest;

  // Foregrounds, most to least emphasis.
  final Color fg;
  final Color fgMuted;
  final Color fgSubtle;

  final Color outline;

  final Color accent;
  final Color accentStrong;
  final Color accentTint;

  // Severity tiers. Order matters clinically:
  // contraindicated > avoid > caution > monitor > safe.
  final Color contraindicated;
  final Color contraindicatedTint;
  final Color avoid;
  final Color avoidTint;
  final Color caution;
  final Color cautionTint;
  final Color monitor;
  final Color monitorTint;
  final Color safe;
  final Color safeTint;

  static const light = V2Palette(
    bg: V2Colors.bg,
    surface: V2Colors.surface,
    surfaceHigh: V2Colors.bg,
    surfaceHighest: V2Colors.surfaceContainerHighest,
    fg: V2Colors.fg,
    fgMuted: V2Colors.fgMuted,
    fgSubtle: V2Colors.fgSubtle,
    outline: V2Colors.outline,
    accent: V2Colors.accent,
    accentStrong: V2Colors.accentStrong,
    accentTint: V2Colors.accentTint,
    contraindicated: V2Colors.contraindicated,
    contraindicatedTint: V2Colors.contraindicatedTint,
    avoid: V2Colors.avoid,
    avoidTint: V2Colors.avoidTint,
    caution: V2Colors.caution,
    cautionTint: V2Colors.cautionTint,
    monitor: V2Colors.monitor,
    monitorTint: V2Colors.monitorTint,
    safe: V2Colors.safe,
    safeTint: V2Colors.safeTint,
  );

  static const dark = V2Palette(
    bg: V2Colors.bgDark,
    surface: V2Colors.surfaceDark,
    surfaceHigh: V2Colors.surfaceContainerHighDark,
    surfaceHighest: V2Colors.surfaceContainerHighestDark,
    fg: V2Colors.fgDark,
    fgMuted: V2Colors.fgMutedDark,
    fgSubtle: V2Colors.fgSubtleDark,
    outline: V2Colors.outlineDark,
    accent: V2Colors.accentDark,
    accentStrong: V2Colors.accentStrongDark,
    accentTint: V2Colors.accentTintDark,
    contraindicated: V2Colors.contraindicatedDark,
    contraindicatedTint: V2Colors.contraindicatedTintDark,
    avoid: V2Colors.avoidDark,
    avoidTint: V2Colors.avoidTintDark,
    caution: V2Colors.cautionDark,
    cautionTint: V2Colors.cautionTintDark,
    monitor: V2Colors.monitorDark,
    monitorTint: V2Colors.monitorTintDark,
    safe: V2Colors.safeDark,
    safeTint: V2Colors.safeTintDark,
  );

  static V2Palette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  V2Palette copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHigh,
    Color? surfaceHighest,
    Color? fg,
    Color? fgMuted,
    Color? fgSubtle,
    Color? outline,
    Color? accent,
    Color? accentStrong,
    Color? accentTint,
    Color? contraindicated,
    Color? contraindicatedTint,
    Color? avoid,
    Color? avoidTint,
    Color? caution,
    Color? cautionTint,
    Color? monitor,
    Color? monitorTint,
    Color? safe,
    Color? safeTint,
  }) {
    return V2Palette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceHighest: surfaceHighest ?? this.surfaceHighest,
      fg: fg ?? this.fg,
      fgMuted: fgMuted ?? this.fgMuted,
      fgSubtle: fgSubtle ?? this.fgSubtle,
      outline: outline ?? this.outline,
      accent: accent ?? this.accent,
      accentStrong: accentStrong ?? this.accentStrong,
      accentTint: accentTint ?? this.accentTint,
      contraindicated: contraindicated ?? this.contraindicated,
      contraindicatedTint: contraindicatedTint ?? this.contraindicatedTint,
      avoid: avoid ?? this.avoid,
      avoidTint: avoidTint ?? this.avoidTint,
      caution: caution ?? this.caution,
      cautionTint: cautionTint ?? this.cautionTint,
      monitor: monitor ?? this.monitor,
      monitorTint: monitorTint ?? this.monitorTint,
      safe: safe ?? this.safe,
      safeTint: safeTint ?? this.safeTint,
    );
  }

  /// Interpolates so a light↔dark switch animates instead of snapping.
  @override
  V2Palette lerp(covariant V2Palette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return V2Palette(
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      surfaceHigh: mix(surfaceHigh, other.surfaceHigh),
      surfaceHighest: mix(surfaceHighest, other.surfaceHighest),
      fg: mix(fg, other.fg),
      fgMuted: mix(fgMuted, other.fgMuted),
      fgSubtle: mix(fgSubtle, other.fgSubtle),
      outline: mix(outline, other.outline),
      accent: mix(accent, other.accent),
      accentStrong: mix(accentStrong, other.accentStrong),
      accentTint: mix(accentTint, other.accentTint),
      contraindicated: mix(contraindicated, other.contraindicated),
      contraindicatedTint: mix(contraindicatedTint, other.contraindicatedTint),
      avoid: mix(avoid, other.avoid),
      avoidTint: mix(avoidTint, other.avoidTint),
      caution: mix(caution, other.caution),
      cautionTint: mix(cautionTint, other.cautionTint),
      monitor: mix(monitor, other.monitor),
      monitorTint: mix(monitorTint, other.monitorTint),
      safe: mix(safe, other.safe),
      safeTint: mix(safeTint, other.safeTint),
    );
  }
}

extension V2PaletteContext on BuildContext {
  /// The brightness-resolved v2 palette.
  ///
  /// Throws when `V2Theme` is not an ancestor. That is deliberate: a silent
  /// fallback to the light palette would reintroduce exactly the invisible
  /// light-on-dark failure this replaces, and would do it in whichever test or
  /// screen forgot the theme — the hardest place to notice it.
  V2Palette get v2 {
    final palette = Theme.of(this).extension<V2Palette>();
    assert(
      palette != null,
      'No V2Palette in scope. Wrap the widget in V2Theme.light or '
      'V2Theme.dark — a light-mode fallback would hide the bug.',
    );
    return palette ?? V2Palette.of(Theme.of(this).brightness);
  }
}
