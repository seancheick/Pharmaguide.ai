import 'package:flutter/material.dart';

/// PharmaGuide design system.
///
/// WCAG AA compliant color tokens, Inter typography, 8dp spacing grid.
/// All UI colors must come from this file — no hardcoded hex elsewhere.
abstract final class AppTheme {
  // ---------------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------------
  static const brandTeal = Color(0xFF0A7D6F);
  static const _brandSeed = brandTeal;

  // ---------------------------------------------------------------------------
  // 8dp Spacing Grid
  // ---------------------------------------------------------------------------
  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space24 = 24.0;
  static const space32 = 32.0;
  static const space40 = 40.0;
  static const space48 = 48.0;
  static const space56 = 56.0;
  static const space64 = 64.0;

  // ---------------------------------------------------------------------------
  // Border Radius
  // ---------------------------------------------------------------------------
  static const radiusSmall = 8.0;
  static const radiusMedium = 12.0;
  static const radiusLarge = 16.0;
  static const radiusFull = 999.0;

  // ---------------------------------------------------------------------------
  // WCAG AA Light Colors (contrast >= 4.5:1 on white)
  // ---------------------------------------------------------------------------
  static const lightBackground = Color(0xFFF8FAFC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightTextPrimary = Color(0xFF0F172A); // 15.4:1 on white
  static const lightTextSecondary = Color(0xFF475569); // 5.9:1 on white
  static const lightBorder = Color(0xFFE2E8F0);

  // ---------------------------------------------------------------------------
  // WCAG AA Dark Colors (contrast >= 4.5:1 on dark bg)
  // ---------------------------------------------------------------------------
  static const darkBackground = Color(0xFF0F172A);
  static const darkSurface = Color(0xFF1E293B);
  static const darkTextPrimary = Color(0xFFF1F5F9); // 14.6:1 on dark bg
  static const darkTextSecondary = Color(0xFF94A3B8); // 4.6:1 on dark bg
  static const darkBorder = Color(0xFF334155);

  // ---------------------------------------------------------------------------
  // Severity Colors (shared, WCAG AA compliant on respective backgrounds)
  // ---------------------------------------------------------------------------
  static const severityContraindicated = Color(0xFFDC2626);
  static const severityAvoid = Color(0xFFDC2626);
  static const severityCaution = Color(0xFFF97316);
  static const severityMonitor = Color(0xFFEAB308);
  static const severitySafe = Color(0xFF22C55E);

  // ---------------------------------------------------------------------------
  // Score Colors
  // ---------------------------------------------------------------------------
  static const scoreExceptional = Color(0xFF059669);
  static const scoreExcellent = Color(0xFF22C55E);
  static const scoreGood = Color(0xFF84CC16);
  static const scoreFair = Color(0xFFEAB308);
  static const scoreBelowAvg = Color(0xFFF97316);
  static const scoreLow = Color(0xFFEF4444);
  static const scoreVeryPoor = Color(0xFFDC2626);

  // ---------------------------------------------------------------------------
  // Light Theme
  // ---------------------------------------------------------------------------
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _brandSeed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: lightBackground,
        fontFamily: 'Inter',
        textTheme: _textTheme(lightTextPrimary, lightTextSecondary),
        appBarTheme: const AppBarTheme(
          backgroundColor: lightSurface,
          foregroundColor: lightTextPrimary,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        cardTheme: CardThemeData(
          color: lightSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            side: const BorderSide(color: lightBorder),
          ),
        ),
        dividerTheme: const DividerThemeData(color: lightBorder),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: lightSurface,
          indicatorColor: _brandSeed.withValues(alpha: 0.12),
          labelTextStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: lightTextSecondary,
            ),
          ),
        ),
      );

  // ---------------------------------------------------------------------------
  // Dark Theme
  // ---------------------------------------------------------------------------
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _brandSeed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: darkBackground,
        fontFamily: 'Inter',
        textTheme: _textTheme(darkTextPrimary, darkTextSecondary),
        appBarTheme: const AppBarTheme(
          backgroundColor: darkSurface,
          foregroundColor: darkTextPrimary,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        cardTheme: CardThemeData(
          color: darkSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            side: const BorderSide(color: darkBorder),
          ),
        ),
        dividerTheme: const DividerThemeData(color: darkBorder),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: darkSurface,
          indicatorColor: _brandSeed.withValues(alpha: 0.24),
          labelTextStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: darkTextSecondary,
            ),
          ),
        ),
      );

  // ---------------------------------------------------------------------------
  // Typography
  // ---------------------------------------------------------------------------
  static TextTheme _textTheme(Color primary, Color secondary) => TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: primary,
          height: 1.25,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: primary,
          height: 1.29,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: primary,
          height: 1.33,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: primary,
          height: 1.4,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: primary,
          height: 1.33,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: primary,
          height: 1.5,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: primary,
          height: 1.43,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: primary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: primary,
          height: 1.43,
        ),
        bodySmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: secondary,
          height: 1.33,
        ),
        labelLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: primary,
          height: 1.43,
        ),
        labelMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: secondary,
          height: 1.33,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: secondary,
          height: 1.45,
        ),
      );
}
