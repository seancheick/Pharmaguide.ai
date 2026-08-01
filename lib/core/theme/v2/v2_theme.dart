import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 theme — Material 3 ThemeData built from v2 tokens.
abstract final class V2Theme {
  static ThemeData get light => _build(brightness: Brightness.light);
  static ThemeData get dark => _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final palette = V2Palette.of(brightness);
    final bg = isDark ? V2Colors.bgDark : V2Colors.bg;
    final surface = isDark ? V2Colors.surfaceDark : V2Colors.surface;
    final fg = isDark ? V2Colors.fgDark : V2Colors.fg;
    final fgMuted = isDark ? V2Colors.fgMutedDark : V2Colors.fgMuted;
    final accent = isDark ? V2Colors.accentDark : V2Colors.accent;
    final accentTint = isDark ? V2Colors.accentTintDark : V2Colors.accentTint;
    final outline = isDark ? V2Colors.outlineDark : V2Colors.outline;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: palette.onAccent,
      primaryContainer: accentTint,
      onPrimaryContainer: accent,
      secondary: accent,
      onSecondary: palette.onAccent,
      secondaryContainer: accentTint,
      onSecondaryContainer: accent,
      // Resolved per brightness. Previously pinned to the light-mode values,
      // which put `safe` at 2.59:1 and `contraindicated` at 2.38:1 on the dark
      // surface — below even the 3:1 large-text floor.
      tertiary: palette.safe,
      onTertiary: palette.onSafe,
      error: palette.contraindicated,
      onError: palette.onContraindicated,
      surface: surface,
      onSurface: fg,
      surfaceContainerLowest: bg,
      surfaceContainerLow: isDark
          ? V2Colors.surfaceContainerLowDark
          : V2Colors.surface,
      surfaceContainer: surface,
      surfaceContainerHigh: isDark ? V2Colors.surfaceContainerHighDark : bg,
      surfaceContainerHighest: isDark
          ? V2Colors.surfaceContainerHighestDark
          : V2Colors.surfaceContainerHighest,
      onSurfaceVariant: fgMuted,
      outline: outline,
      outlineVariant: outline,
    );

    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final textTheme = GoogleFonts.geistTextTheme(base.textTheme).copyWith(
      displayLarge: V2Typography.display(color: fg),
      displayMedium: V2Typography.displaySm(color: fg),
      displaySmall: V2Typography.displayXs(color: fg),
      headlineLarge: V2Typography.title(color: fg),
      headlineMedium: V2Typography.titleSm(color: fg),
      headlineSmall: V2Typography.bodyXl(color: fg),
      titleLarge: V2Typography.title(color: fg),
      titleMedium: V2Typography.bodyMedium(color: fg),
      titleSmall: V2Typography.label(color: fg),
      bodyLarge: V2Typography.bodyXl(color: fg),
      bodyMedium: V2Typography.body(color: fg),
      bodySmall: V2Typography.bodySm(color: fgMuted),
      labelLarge: V2Typography.label(color: fg),
      labelMedium: V2Typography.caption(color: fgMuted),
      labelSmall: V2Typography.overline(color: fgMuted),
    );

    return base.copyWith(
      colorScheme: colorScheme,
      // The brightness-resolved palette every widget reads via `context.v2`.
      extensions: <ThemeExtension<dynamic>>[palette],
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: V2Typography.titleSm(color: fg),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          side: BorderSide(color: outline, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: palette.onAccent,
          textStyle: V2Typography.label(),
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space24,
            vertical: V2Spacing.space12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.4)),
          textStyle: V2Typography.label(),
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space24,
            vertical: V2Spacing.space12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: V2Typography.label(),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(V2Spacing.radiusSheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V2Spacing.radiusSheet),
        ),
        titleTextStyle: V2Typography.title(color: fg),
        contentTextStyle: V2Typography.body(color: fg),
      ),
      dividerTheme: DividerThemeData(
        color: outline,
        thickness: 1,
        space: V2Spacing.space24,
      ),
      iconTheme: IconThemeData(color: fg, size: 20),
      primaryIconTheme: IconThemeData(color: fg, size: 20),
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // iOS uses Flutter's platform default. Keep only the Android
          // override here so this stays compatible across Flutter SDKs.
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
