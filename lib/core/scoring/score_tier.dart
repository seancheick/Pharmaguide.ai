// Score-tier model: 0–100 product score → 1 of 6 named tiers.
//
// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T9
// (locked tier table 2026-04-29).
//
// The tier system replaces the pre-S2.2 score-ring visualization with
// a compact text-based "● 90/100 Exceptional · description" line. Six
// tiers with explicit color + label + one-line description so the
// score is immediately interpretable on the hero card without the user
// having to learn the percentage scale.
//
// Tier table:
//   90–100  Exceptional  Deep Green  High-quality ingredients, ...
//   80–89   Excellent    Green       Well-formulated with ...
//   70–79   Good         Teal        Reliable option with ...
//   60–69   Fair         Yellow      Adequate formulation with ...
//   50–59   Low Quality  Orange      Notable concerns — ...
//   0–49    Poor         Red         Significant concerns ...
//
// Boundary semantics: thresholds are inclusive at the floor — 90 is
// the bottom of Exceptional, 89 is the top of Excellent. Boundary
// tests at 49/50, 59/60, 69/70, 79/80, 89/90 lock this so a future
// `>` vs `>=` regression is impossible to silently introduce.

import 'package:flutter/material.dart';

/// A score may be available while formula-wide input confidence is low.
/// Keep the number for transparency, but suppress confident tier adjectives.
bool hasLimitedAssessmentConfidence(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  return normalized == 'low' ||
      normalized == 'limited' ||
      normalized == 'very_low';
}

/// 6-tier classification of a 0–100 product score. Values flow through
/// [tierForScore]; never construct a tier from outside this module.
enum ScoreTier { exceptional, excellent, good, fair, lowQuality, poor }

/// Display + theme metadata per tier — all locked from the spec's
/// Tier-Description-Color table.
extension ScoreTierMeta on ScoreTier {
  /// User-facing label rendered next to the score (e.g. "Exceptional").
  /// Uses Title Case for "Low Quality" because it reads as a single
  /// chip; the rest are single words.
  String get label => switch (this) {
    ScoreTier.exceptional => 'Exceptional',
    ScoreTier.excellent => 'Excellent',
    ScoreTier.good => 'Good',
    ScoreTier.fair => 'Fair',
    ScoreTier.lowQuality => 'Low Quality',
    ScoreTier.poor => 'Poor',
  };

  /// One-line description shown under the score line on the hero card.
  /// Sentence-case (no period) so it reads as a label, not a sentence.
  /// Locked copy per the design contract.
  String get description => switch (this) {
    ScoreTier.exceptional =>
      'High-quality ingredients, strong evidence, no major safety concerns',
    ScoreTier.excellent =>
      'Well-formulated with good ingredient quality, solid evidence, clean safety profile',
    ScoreTier.good =>
      'Reliable option with acceptable ingredients and no major red flags',
    ScoreTier.fair =>
      'Adequate formulation with some limitations in quality, evidence, or transparency',
    ScoreTier.lowQuality =>
      'Notable concerns — weaker ingredients, limited evidence, or avoidable additives',
    ScoreTier.poor =>
      'Significant concerns around formulation quality, safety, or transparency',
  };

  /// Non-text tier token — the score dot, pillar bars, and tint fills.
  /// Meets the 3:1 non-text floor on every surface of the given appearance.
  ///
  /// Both ramps are derived from the locked spec colours by holding hue and
  /// saturation and moving ONLY lightness, the same method as the severity
  /// ramp in v2_colors.dart. Dark keeps the spec values unchanged — they
  /// already clear 3:1 on dark surfaces. Light darkens three tiers that did
  /// not (excellent 2.85:1, good 2.87:1, fair 2.78:1).
  ///
  /// Takes a [Brightness] rather than being a bare getter because these are
  /// rendered colours: a plain getter can only hold one appearance, which is
  /// exactly how the whole tier system missed dark mode.
  Color color(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (this) {
      ScoreTier.exceptional => const Color(0xFF059669),
      ScoreTier.excellent => isDark
          ? const Color(0xFF22A06B)
          : const Color(0xFF219B68),
      ScoreTier.good => isDark
          ? const Color(0xFF0EA5A0)
          : const Color(0xFF0D9893),
      ScoreTier.fair => isDark
          ? const Color(0xFFCA8A04)
          : const Color(0xFFB77D04),
      ScoreTier.lowQuality => const Color(0xFFEA580C),
      ScoreTier.poor => const Color(0xFFDC2626),
    };
  }

  /// Accessible foreground for tier-colored TEXT — the score number and the
  /// tier label. Clears 4.5:1 on every surface of the given appearance, so a
  /// prominent score never leans on the large-text exception.
  ///
  /// The dark ramp is the fix for a real defect: these values were authored
  /// for cream surfaces only ("readable on cream", per the original comment)
  /// and were rendered verbatim in dark mode, where every tier failed —
  /// `poor` worst at 2.33:1, below even the 3:1 large-text floor. Three light
  /// values also missed 4.5:1 and are nudged darker here.
  Color textColor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (this) {
      ScoreTier.exceptional => isDark
          ? const Color(0xFF05A074)
          : const Color(0xFF047857),
      ScoreTier.excellent => isDark
          ? const Color(0xFF1BA24D)
          : const Color(0xFF147C3B),
      ScoreTier.good => isDark
          ? const Color(0xFF149D92)
          : const Color(0xFF0F766E),
      ScoreTier.fair => isDark
          ? const Color(0xFFC97A09)
          : const Color(0xFF9A5E07),
      ScoreTier.lowQuality => isDark
          ? const Color(0xFFF15C1E)
          : const Color(0xFFC0400C),
      ScoreTier.poor => isDark
          ? const Color(0xFFE76161)
          : const Color(0xFFB91C1C),
    };
  }
}

/// Map a score to its tier. Inclusive at the floor — 90 → Exceptional,
/// 89 → Excellent. Out-of-range inputs clamp gracefully:
///   ≥100  → Exceptional   (e.g., over-the-cap score from rounding)
///   <0    → Poor          (e.g., a defaulted/uninitialized score)
ScoreTier tierForScore(int score) {
  if (score >= 90) return ScoreTier.exceptional;
  if (score >= 80) return ScoreTier.excellent;
  if (score >= 70) return ScoreTier.good;
  if (score >= 60) return ScoreTier.fair;
  if (score >= 50) return ScoreTier.lowQuality;
  return ScoreTier.poor;
}
