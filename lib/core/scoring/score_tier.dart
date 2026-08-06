// Score-tier model for the catalog's six named quality tiers.
//
// The pipeline's `quality_tier` field is authoritative for catalog
// products. A score-derived mapping remains only as an explicitly named
// fallback for old or incomplete cached records.

import 'package:flutter/material.dart';

/// A score may be available while formula-wide input confidence is low.
/// Keep the number for transparency, but suppress confident tier adjectives.
bool hasLimitedAssessmentConfidence(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  return normalized == 'low' ||
      normalized == 'limited' ||
      normalized == 'very_low';
}

/// The six values emitted by the pipeline's `quality_tier` contract.
enum ScoreTier { elite, excellent, strong, acceptable, weak, poor }

/// Display + theme metadata per tier — all locked from the spec's
/// Tier-Description-Color table.
extension ScoreTierMeta on ScoreTier {
  /// User-facing label rendered next to the score.
  String get label => switch (this) {
    ScoreTier.elite => 'Elite',
    ScoreTier.excellent => 'Excellent',
    ScoreTier.strong => 'Strong',
    ScoreTier.acceptable => 'Acceptable',
    ScoreTier.weak => 'Weak',
    ScoreTier.poor => 'Poor',
  };

  /// One-line description shown under the score line on the hero card.
  /// Sentence-case (no period) so it reads as a label, not a sentence.
  /// Locked copy per the design contract.
  String get description => switch (this) {
    ScoreTier.elite =>
      'High-quality ingredients, strong evidence, no major safety concerns',
    ScoreTier.excellent =>
      'Well-formulated with good ingredient quality, solid evidence, clean safety profile',
    ScoreTier.strong =>
      'Reliable option with acceptable ingredients and no major red flags',
    ScoreTier.acceptable =>
      'Adequate formulation with some limitations in quality, evidence, or transparency',
    ScoreTier.weak =>
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
      ScoreTier.elite => const Color(0xFF059669),
      ScoreTier.excellent =>
        isDark ? const Color(0xFF22A06B) : const Color(0xFF219B68),
      ScoreTier.strong =>
        isDark ? const Color(0xFF0EA5A0) : const Color(0xFF0D9893),
      ScoreTier.acceptable =>
        isDark ? const Color(0xFFCA8A04) : const Color(0xFFB77D04),
      ScoreTier.weak => const Color(0xFFEA580C),
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
      ScoreTier.elite =>
        isDark ? const Color(0xFF05A074) : const Color(0xFF047857),
      ScoreTier.excellent =>
        isDark ? const Color(0xFF1BA24D) : const Color(0xFF147C3B),
      ScoreTier.strong =>
        isDark ? const Color(0xFF149D92) : const Color(0xFF0F766E),
      ScoreTier.acceptable =>
        isDark ? const Color(0xFFC97A09) : const Color(0xFF9A5E07),
      ScoreTier.weak =>
        isDark ? const Color(0xFFF15C1E) : const Color(0xFFC0400C),
      ScoreTier.poor =>
        isDark ? const Color(0xFFE76161) : const Color(0xFFB91C1C),
    };
  }
}

ScoreTier? _catalogTierFromLabel(String? value) {
  return switch ((value ?? '').trim().toLowerCase()) {
    'elite' => ScoreTier.elite,
    'excellent' => ScoreTier.excellent,
    'strong' => ScoreTier.strong,
    'acceptable' => ScoreTier.acceptable,
    'weak' => ScoreTier.weak,
    'poor' => ScoreTier.poor,
    _ => null,
  };
}

/// Resolve a catalog tier, preferring the pipeline's shipped value.
///
/// The fallback exists for old cached records that predate `quality_tier`.
ScoreTier catalogTier({
  required String? qualityTier,
  required int legacyScore,
}) {
  return _catalogTierFromLabel(qualityTier) ?? legacyTierForScore(legacyScore);
}

/// Score-derived fallback for old or incomplete records only.
///
/// These thresholds mirror the pipeline bands. Out-of-range inputs clamp
/// naturally to [ScoreTier.elite] or [ScoreTier.poor].
ScoreTier legacyTierForScore(int score) {
  if (score >= 95) return ScoreTier.elite;
  if (score >= 90) return ScoreTier.excellent;
  if (score >= 80) return ScoreTier.strong;
  if (score >= 70) return ScoreTier.acceptable;
  if (score >= 55) return ScoreTier.weak;
  return ScoreTier.poor;
}
