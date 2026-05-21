import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// v2 typography — fixed scale, weight discipline enforced.
///
/// ### Governance (locked, do not relax)
/// - **Geist Sans** is the primary reading font.
/// - **Newsreader** (serif) is an **accent tool only** — hero headlines,
///   onboarding emotional moments, empty-state titles, celebratory moments.
///   NEVER on warnings, ingredient lists, settings, navigation, buttons,
///   or anything a user reads to make a clinical decision.
/// - **Geist Mono** is metadata only — eyebrows, evidence labels, severity
///   names, timestamps, compact diagnostics.
/// - **Weights:** 400 and 500 only. Never 600. Never 700. Never italic.
/// - **Scale:** 40 / 32 / 24 / 20 / 18 / 16 / 14 / 12 / 10. No other sizes.
abstract final class V2Typography {
  // Font scale — fixed.
  static const double size40 = 40;
  static const double size32 = 32;
  static const double size24 = 24;
  static const double size20 = 20;
  static const double size18 = 18;
  static const double size16 = 16;
  static const double size14 = 14;
  static const double size12 = 12;
  static const double size10 = 10;

  // Line heights.
  static const double lhDisplay = 1.05;
  static const double lhTight = 1.15;
  static const double lhSnug = 1.30;
  static const double lhNormal = 1.50;
  static const double lhRelaxed = 1.65;

  // Letter spacing.
  static const double tsDisplay = -0.022 * 16;
  static const double tsTight = -0.012 * 16;
  static const double tsNormal = 0.0;
  static const double tsEyebrow = 0.12 * 16;

  // ---------------------------------------------------------------------------
  // Display (Newsreader serif) — accent contexts only.
  // ---------------------------------------------------------------------------

  static TextStyle display({Color? color}) => GoogleFonts.newsreader(
    fontSize: size40,
    fontWeight: FontWeight.w400,
    height: lhDisplay,
    letterSpacing: tsDisplay,
    color: color,
  );

  static TextStyle displaySm({Color? color}) => GoogleFonts.newsreader(
    fontSize: size32,
    fontWeight: FontWeight.w400,
    height: lhTight,
    letterSpacing: tsDisplay,
    color: color,
  );

  static TextStyle displayXs({Color? color}) => GoogleFonts.newsreader(
    fontSize: size24,
    fontWeight: FontWeight.w400,
    height: lhTight,
    letterSpacing: tsTight,
    color: color,
  );

  // ---------------------------------------------------------------------------
  // UI (Geist Sans) — primary reading font, 400/500 only.
  // ---------------------------------------------------------------------------

  static TextStyle title({Color? color}) => GoogleFonts.geist(
    fontSize: size24,
    fontWeight: FontWeight.w500,
    height: lhSnug,
    letterSpacing: tsTight,
    color: color,
  );

  static TextStyle titleSm({Color? color}) => GoogleFonts.geist(
    fontSize: size20,
    fontWeight: FontWeight.w500,
    height: lhSnug,
    letterSpacing: tsTight,
    color: color,
  );

  static TextStyle bodyXl({Color? color}) => GoogleFonts.geist(
    fontSize: size18,
    fontWeight: FontWeight.w400,
    height: lhNormal,
    color: color,
  );

  static TextStyle body({Color? color}) => GoogleFonts.geist(
    fontSize: size16,
    fontWeight: FontWeight.w400,
    height: lhNormal,
    color: color,
  );

  static TextStyle bodyMedium({Color? color}) => GoogleFonts.geist(
    fontSize: size16,
    fontWeight: FontWeight.w500,
    height: lhNormal,
    color: color,
  );

  static TextStyle bodySm({Color? color}) => GoogleFonts.geist(
    fontSize: size14,
    fontWeight: FontWeight.w400,
    height: lhNormal,
    color: color,
  );

  static TextStyle label({Color? color}) => GoogleFonts.geist(
    fontSize: size14,
    fontWeight: FontWeight.w500,
    height: lhSnug,
    color: color,
  );

  static TextStyle caption({Color? color}) => GoogleFonts.geist(
    fontSize: size12,
    fontWeight: FontWeight.w400,
    height: lhSnug,
    color: color,
  );

  // ---------------------------------------------------------------------------
  // Mono (Geist Mono) — metadata only.
  // ---------------------------------------------------------------------------

  /// Eyebrow (12pt mono caps, 500). Caller must uppercase the string.
  static TextStyle eyebrow({Color? color}) => GoogleFonts.geistMono(
    fontSize: size12,
    fontWeight: FontWeight.w500,
    height: lhSnug,
    letterSpacing: tsEyebrow,
    color: color,
  );

  static TextStyle overline({Color? color}) => GoogleFonts.geistMono(
    fontSize: size10,
    fontWeight: FontWeight.w500,
    height: lhSnug,
    letterSpacing: tsEyebrow,
    color: color,
  );

  static TextStyle monoData({Color? color}) => GoogleFonts.geistMono(
    fontSize: size14,
    fontWeight: FontWeight.w500,
    height: lhSnug,
    color: color,
    // Tabular figures — fixed-width digits so "10/10" and "7/10" align
    // identically at the right edge across pillars / rows.
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
