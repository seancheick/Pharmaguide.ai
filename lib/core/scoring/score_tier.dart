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

  /// Tier color used for the score dot, tier-label text, and pillar
  /// bars. Hand-picked to read distinctly across light + dark surfaces:
  ///   Exceptional → deep green   #059669
  ///   Excellent   → green        #22A06B
  ///   Good        → teal         #0EA5A0
  ///   Fair        → yellow       #CA8A04
  ///   Low Quality → orange       #EA580C
  ///   Poor        → red          #DC2626
  Color get color => switch (this) {
    ScoreTier.exceptional => const Color(0xFF059669),
    ScoreTier.excellent => const Color(0xFF22A06B),
    ScoreTier.good => const Color(0xFF0EA5A0),
    ScoreTier.fair => const Color(0xFFCA8A04),
    ScoreTier.lowQuality => const Color(0xFFEA580C),
    ScoreTier.poor => const Color(0xFFDC2626),
  };
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
