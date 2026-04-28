import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PharmaGuide design system.
///
/// **Direction:** soft clinical premium — Apple Health meets a medical journal.
/// Layered M3 surface roles, warm neutrals, restrained motion, legible type.
///
/// All UI colors must come from this file (or the `ColorScheme` it produces).
/// No hardcoded hex outside the `core/theme` and `core/constants` folders.
///
/// ---
/// ### Design layers
/// 1. **Raw tokens**   — spacing, radius, base hex values
/// 2. **Semantic**     — surface ladder, text, outlines, severity, evidence
/// 3. **M3 mapping**   — `ColorScheme`, `TextTheme`, component themes
/// 4. **Product**      — `PGCard`, `PGInteractionCard`, etc. (see `core/widgets`)
///
/// `AppTheme` handles layers 1-3. Product widgets live in `core/widgets/pg_*`.
abstract final class AppTheme {
  // ---------------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------------

  /// Primary brand color — also used in splash, app icon, push notifications.
  /// Do not change without updating `flutter_native_splash` and launcher icon
  /// regenerations in `pubspec.yaml`.
  static const brandTeal = Color(0xFF0A7D6F);

  /// Dark-mode primary (lighter seafoam for legibility on dark surfaces).
  static const brandTealDark = Color(0xFF7AD2C7);

  // ---------------------------------------------------------------------------
  // Spacing — 8dp grid (with 4dp half-steps)
  // ---------------------------------------------------------------------------
  static const space2 = 2.0;
  static const space4 = 4.0;
  static const space6 = 6.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space20 = 20.0;
  static const space24 = 24.0;
  static const space32 = 32.0;
  static const space40 = 40.0;
  static const space48 = 48.0;
  static const space56 = 56.0;
  static const space64 = 64.0;

  // ---------------------------------------------------------------------------
  // Radius
  // ---------------------------------------------------------------------------
  static const radiusSmall = 8.0;
  static const radiusMedium = 12.0;
  static const radiusLarge = 16.0;
  static const radiusXLarge = 24.0;
  static const radiusXXLarge = 32.0;
  static const radiusFull = 999.0;

  // ===========================================================================
  // LIGHT PALETTE
  // ===========================================================================

  /// Warm off-white scaffold — builds trust without feeling clinical-cold.
  static const lightBackground = Color(0xFFF5F7F8);

  // --- Surface ladder (M3 tone-based) ---
  /// Primary card surface (kept == white for backward compat).
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceLowest = Color(0xFFFFFFFF);
  static const lightSurfaceLow = Color(0xFFFBFCFD);
  static const lightSurfaceHigh = Color(0xFFEEF2F4);
  static const lightSurfaceHighest = Color(0xFFE3E8EB);
  static const lightSurfaceBright = Color(0xFFFFFFFF);
  static const lightSurfaceDim = Color(0xFFEEF2F4);

  // --- Text ---
  static const lightTextPrimary = Color(0xFF0F172A); // 15.4:1 on white
  static const lightTextSecondary = Color(0xFF475569); // 5.9:1 on white
  static const lightTextTertiary = Color(0xFF7C8792); // metadata only

  // --- Outlines ---
  /// Legacy opaque border — kept for backward compat with older screens.
  static const lightBorder = Color(0xFFE2E8F0);

  /// 12% ink — card/input borders (use over `lightBorder` in new code).
  static const lightOutline = Color(0x1F0F172A);

  /// 8% ink — subtle dividers, quiet separation.
  static const lightOutlineSoft = Color(0x140F172A);

  // ===========================================================================
  // DARK PALETTE
  //
  // Cool blue-gray rather than iOS-neutral systemGray. This is intentional —
  // the brand is teal/seafoam, and a strict neutral gray ladder
  // (systemGray6/5/4) clashes with that brand. The cool tint gives the
  // dark theme a coherent atmosphere with the primary color.
  //
  // The *spacing* between tiers (~4–5 luminance points) matches Apple's
  // dark mode ladder (systemGray6→5→4 spans ~5 luminance points), which is
  // what creates the iOS feel of layered depth. We trade hex-exactness for
  // brand coherence; the depth-perception cue is preserved.
  //
  //                            iOS reference          ours
  //   surfaceContainer        systemGray6 #1C1C1E    #11181F (cooler/darker)
  //   surfaceContainerHigh    systemGray5 #2C2C2E    #17202A
  //   surfaceContainerHighest systemGray4 #3A3A3C    #1D2732
  // ===========================================================================

  static const darkBackground = Color(0xFF0B1116);

  static const darkSurface = Color(0xFF11181F);
  static const darkSurfaceLowest = Color(0xFF070B0F);
  static const darkSurfaceLow = Color(0xFF0E141A);
  static const darkSurfaceHigh = Color(0xFF17202A);
  static const darkSurfaceHighest = Color(0xFF1D2732);
  static const darkSurfaceBright = Color(0xFF1C2833);
  static const darkSurfaceDim = Color(0xFF090E13);

  static const darkTextPrimary = Color(0xFFF1F5F9);
  static const darkTextSecondary = Color(0xFF94A3B8);
  static const darkTextTertiary = Color(0xFF64748B);

  static const darkBorder = Color(0xFF334155);
  static const darkOutline = Color(0x1FFFFFFF);
  static const darkOutlineSoft = Color(0x14FFFFFF);

  // ===========================================================================
  // SEVERITY — medical risk (distinct from score)
  // ===========================================================================
  // Keep in sync with `lib/core/constants/severity.dart`.

  static const severityContraindicated = Color(0xFFB91C1C);
  static const severityAvoid = Color(0xFFC2410C);
  static const severityCaution = Color(0xFFD97706);
  static const severityMonitor = Color(0xFFCA8A04);
  // Neutral slate — calm, not alarming. Used for profile-less rendering
  // of rules whose intrinsic severity is avoid/caution but no user
  // profile match exists (see pipeline schema v5.2 severity_contextual).
  static const severityInformational = Color(0xFF64748B);
  static const severitySafe = Color(0xFF15803D);

  // ===========================================================================
  // SCORE — quality/fit rating (distinct hues from severity)
  // ===========================================================================

  static const scoreExceptional = Color(0xFF059669);
  static const scoreExcellent = Color(0xFF22A06B);
  static const scoreGood = Color(0xFF65A30D);
  static const scoreFair = Color(0xFFCA8A04);
  static const scoreBelowAvg = Color(0xFFEA580C);
  static const scoreLow = Color(0xFFDC2626);
  static const scoreVeryPoor = Color(0xFF991B1B);

  // ===========================================================================
  // PHARMA SEMANTIC TOKENS
  // ===========================================================================

  /// "We don't have enough data" state — NOT gray (reads disabled), NOT red
  /// (reads dangerous). Neutral indigo = honest unknown.
  static const insufficientData = Color(0xFF7C6CBF);
  static const insufficientDataDark = Color(0xFF9B8ED6);

  /// Evidence levels — visual trust hierarchy.
  static const evidenceStrong = brandTeal; // RCT / meta-analysis
  static const evidenceGood = Color(0xFF4C6A6A); // observational
  static const evidenceTheoretical = Color(0xFF7C8792); // mechanism-only

  /// Disclaimer / informational strip color.
  static const info = Color(0xFF0369A1);

  /// Focus ring color and opacity (keyboard / switch-control a11y).
  static const focusRing = brandTeal;
  static const focusRingOpacity = 0.35;

  // ===========================================================================
  // COLOR SCHEMES
  // ===========================================================================

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: brandTeal,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFD6EFEB),
    onPrimaryContainer: Color(0xFF062E2A),
    secondary: Color(0xFF4C6A6A),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFDCE8E7),
    onSecondaryContainer: Color(0xFF1E3131),
    tertiary: Color(0xFF5D6B85),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFE0E7F2),
    onTertiaryContainer: Color(0xFF1F2937),
    error: severityContraindicated,
    onError: Colors.white,
    errorContainer: Color(0xFFFEE2E2),
    onErrorContainer: Color(0xFF7F1D1D),
    surface: lightSurface,
    onSurface: lightTextPrimary,
    onSurfaceVariant: lightTextSecondary,
    outline: lightOutline,
    outlineVariant: lightOutlineSoft,
    shadow: Color(0x14000000),
    scrim: Color(0x52000000),
    inverseSurface: Color(0xFF1A222C),
    onInverseSurface: Color(0xFFF5F7FA),
    inversePrimary: brandTealDark,
    surfaceTint: brandTeal,
    surfaceContainerLowest: lightSurfaceLowest,
    surfaceContainerLow: lightSurfaceLow,
    surfaceContainer: lightSurface,
    surfaceContainerHigh: lightSurfaceHigh,
    surfaceContainerHighest: lightSurfaceHighest,
    surfaceBright: lightSurfaceBright,
    surfaceDim: lightSurfaceDim,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: brandTealDark,
    onPrimary: Color(0xFF052F2B),
    primaryContainer: Color(0xFF123E3A),
    onPrimaryContainer: Color(0xFFD6EFEB),
    secondary: Color(0xFFB7CCCA),
    onSecondary: Color(0xFF223332),
    secondaryContainer: Color(0xFF243736),
    onSecondaryContainer: Color(0xFFDCE8E7),
    tertiary: Color(0xFFC0C8D8),
    onTertiary: Color(0xFF273142),
    tertiaryContainer: Color(0xFF2A3446),
    onTertiaryContainer: Color(0xFFE0E7F2),
    error: Color(0xFFF0A5A5),
    onError: Color(0xFF601414),
    errorContainer: Color(0xFF7F1D1D),
    onErrorContainer: Color(0xFFFEE2E2),
    surface: darkSurface,
    onSurface: darkTextPrimary,
    onSurfaceVariant: darkTextSecondary,
    outline: darkOutline,
    outlineVariant: darkOutlineSoft,
    shadow: Color(0x66000000),
    scrim: Color(0x99000000),
    inverseSurface: Color(0xFFF3F6F8),
    onInverseSurface: Color(0xFF111827),
    inversePrimary: brandTeal,
    surfaceTint: brandTealDark,
    surfaceContainerLowest: darkSurfaceLowest,
    surfaceContainerLow: darkSurfaceLow,
    surfaceContainer: darkSurface,
    surfaceContainerHigh: darkSurfaceHigh,
    surfaceContainerHighest: darkSurfaceHighest,
    surfaceBright: darkSurfaceBright,
    surfaceDim: darkSurfaceDim,
  );

  // ===========================================================================
  // THEMES
  // ===========================================================================

  static ThemeData get light => _build(
        scheme: _lightScheme,
        background: lightBackground,
        textPrimary: lightTextPrimary,
        textSecondary: lightTextSecondary,
        textTertiary: lightTextTertiary,
        outlineSoft: lightOutlineSoft,
        outline: lightOutline,
        surface: lightSurface,
        surfaceLow: lightSurfaceLow,
        surfaceHigh: lightSurfaceHigh,
        filledButtonBg: brandTeal,
        filledButtonFg: Colors.white,
        navIndicator: _withAlpha(brandTeal, 0.12),
        navIconActive: brandTeal,
        overlayStyle: SystemUiOverlayStyle.dark,
      );

  static ThemeData get dark => _build(
        scheme: _darkScheme,
        background: darkBackground,
        textPrimary: darkTextPrimary,
        textSecondary: darkTextSecondary,
        textTertiary: darkTextTertiary,
        outlineSoft: darkOutlineSoft,
        outline: darkOutline,
        surface: darkSurface,
        surfaceLow: darkSurfaceLow,
        surfaceHigh: darkSurfaceHigh,
        filledButtonBg: brandTealDark,
        filledButtonFg: const Color(0xFF052F2B),
        navIndicator: _withAlpha(brandTealDark, 0.18),
        navIconActive: const Color(0xFF9EE5DB),
        overlayStyle: SystemUiOverlayStyle.light,
      );

  static ThemeData _build({
    required ColorScheme scheme,
    required Color background,
    required Color textPrimary,
    required Color textSecondary,
    required Color textTertiary,
    required Color outlineSoft,
    required Color outline,
    required Color surface,
    required Color surfaceLow,
    required Color surfaceHigh,
    required Color filledButtonBg,
    required Color filledButtonFg,
    required Color navIndicator,
    required Color navIconActive,
    required SystemUiOverlayStyle overlayStyle,
  }) {
    final textTheme = _textTheme(
      primary: textPrimary,
      secondary: textSecondary,
      tertiary: textTertiary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      fontFamily: 'Inter',
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      focusColor: _withAlpha(scheme.primary, focusRingOpacity),
      highlightColor: _withAlpha(scheme.primary, 0.06),
      hoverColor: _withAlpha(scheme.primary, 0.04),

      // -------------------------------------------------------------------
      // App bar — flat, no auto-tint, matches scaffold.
      // -------------------------------------------------------------------
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        titleSpacing: space16,
        systemOverlayStyle: overlayStyle,
        iconTheme: IconThemeData(color: textPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: textPrimary, size: 22),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
          color: textPrimary,
          height: 1.34,
        ),
      ),

      // -------------------------------------------------------------------
      // Cards — soft outline, no M3 auto-tint, no shadow by default.
      // -------------------------------------------------------------------
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: BorderSide(color: outlineSoft, width: 0.8),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: outlineSoft,
        thickness: 0.8,
        space: 1,
      ),

      // -------------------------------------------------------------------
      // Navigation bar — the default one (use PGFrostedNavBar for Apple-style
      // frosted glass).
      // -------------------------------------------------------------------
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        indicatorColor: navIndicator,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Inter',
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: 0.1,
            color: selected ? navIconActive : textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? navIconActive : textSecondary,
          );
        }),
      ),

      // -------------------------------------------------------------------
      // Inputs — filled, soft border, big focus ring.
      // -------------------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLow,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: space16,
          vertical: space16,
        ),
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: textTertiary,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
        floatingLabelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: BorderSide(color: outlineSoft, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: BorderSide(color: outlineSoft, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: BorderSide(color: scheme.error, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
      ),

      // -------------------------------------------------------------------
      // Buttons — pill shape, 52h tap target.
      // -------------------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          backgroundColor: filledButtonBg,
          foregroundColor: filledButtonFg,
          disabledBackgroundColor: surfaceHigh,
          disabledForegroundColor: textTertiary,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusFull),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: space24,
            vertical: space12,
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
          animationDuration: const Duration(milliseconds: 180),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          foregroundColor: textPrimary,
          side: BorderSide(color: outline, width: 1.0),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusFull),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: space24,
            vertical: space12,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: space12,
            vertical: space8,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          minimumSize: const Size(44, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),

      // -------------------------------------------------------------------
      // Chips — pill, soft fill, no checkmark clutter.
      // -------------------------------------------------------------------
      chipTheme: ChipThemeData(
        backgroundColor: surfaceLow,
        selectedColor: _withAlpha(scheme.primary, 0.12),
        disabledColor: surfaceHigh,
        side: BorderSide(color: outlineSoft, width: 0.8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textPrimary,
          letterSpacing: -0.05,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
          letterSpacing: -0.05,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),

      // -------------------------------------------------------------------
      // Bottom sheets — 32 radius, drag handle, no auto-tint.
      // -------------------------------------------------------------------
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        modalBarrierColor: Colors.black54,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: outline,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radiusXXLarge),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXLarge),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: textSecondary,
          height: 1.5,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: surfaceHigh,
        circularTrackColor: surfaceHigh,
      ),

      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: textSecondary,
        textColor: textPrimary,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textPrimary,
          height: 1.4,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: textSecondary,
          height: 1.4,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: space16,
          vertical: space4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return scheme.surfaceContainerHighest;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.surfaceContainerHigh;
        }),
        trackOutlineColor: WidgetStatePropertyAll(outlineSoft),
      ),

      // -------------------------------------------------------------------
      // Page transitions — Cupertino on iOS/macOS for that Apple feel,
      // predictive back on Android (Android 14+).
      // -------------------------------------------------------------------
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }

  // ===========================================================================
  // TYPOGRAPHY
  // ===========================================================================
  //
  // Minimum interactive label size: 12px. Minimum body: 13px. Metadata only
  // below that (never interactive).

  static const _family = 'Inter';

  static TextTheme _textTheme({
    required Color primary,
    required Color secondary,
    required Color tertiary,
  }) {
    TextStyle base(
      double size,
      FontWeight weight, {
      double? letter,
      double? height,
      Color? color,
    }) {
      return TextStyle(
        fontFamily: _family,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letter,
        height: height,
        color: color ?? primary,
      );
    }

    return TextTheme(
      // Display — hero moments, onboarding, scan success
      displayLarge: base(34, FontWeight.w700, letter: -0.8, height: 1.18),
      displayMedium: base(30, FontWeight.w700, letter: -0.6, height: 1.2),
      displaySmall: base(26, FontWeight.w700, letter: -0.5, height: 1.22),

      // Headline — screen titles
      headlineLarge: base(28, FontWeight.w700, letter: -0.6, height: 1.22),
      headlineMedium: base(24, FontWeight.w700, letter: -0.4, height: 1.25),
      headlineSmall: base(20, FontWeight.w600, letter: -0.3, height: 1.3),

      // Title — section/card headers
      titleLarge: base(18, FontWeight.w600, letter: -0.2, height: 1.34),
      titleMedium: base(16, FontWeight.w600, letter: -0.15, height: 1.4),
      titleSmall: base(14, FontWeight.w600, letter: -0.1, height: 1.35),

      // Body — long-form reading
      bodyLarge: base(16, FontWeight.w400, letter: -0.1, height: 1.5),
      bodyMedium: base(15, FontWeight.w400, letter: -0.05, height: 1.47),
      bodySmall: base(13, FontWeight.w400, letter: 0.0, height: 1.4,
          color: secondary),

      // Label — buttons, badges, metadata
      labelLarge: base(15, FontWeight.w600, letter: -0.1, height: 1.2),
      labelMedium: base(13, FontWeight.w500, letter: 0.0, height: 1.2,
          color: secondary),
      labelSmall: base(12, FontWeight.w500, letter: 0.1, height: 1.25,
          color: tertiary),
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  /// Returns a copy of [base] with tabular figures enabled.
  ///
  /// Use for any numeric display where columns must align: dosages ("500 mg"),
  /// scores (87, 92, 76), quantities, durations, percentages.
  ///
  /// ```dart
  /// Text('${dose.amount} ${dose.unit}',
  ///     style: AppTheme.numeric(theme.textTheme.titleLarge!))
  /// ```
  static TextStyle numeric(TextStyle base) {
    return base.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Lightweight wrapper for `Color.withValues(alpha: ...)`.
  static Color _withAlpha(Color base, double alpha) =>
      base.withValues(alpha: alpha);
}
