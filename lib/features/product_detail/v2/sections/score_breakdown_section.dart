// Phase 11.7d.1 — ScoreBreakdown section adapter.
//
// V2 mirror of production's `ScoreBreakdownCard`. Composes the v2 PGScoreBreakdownCard
// from the 4 pillar scores + section_breakdown blob + trust flags +
// mappedCoverage + heroScore.
//
// Production widget inputs (verbatim port — no new logic):
//   - ingredientQuality  (max 25)  "Form, dosage, and bioavailability"
//   - safetyPurity       (max 30)  "Free from harmful ingredients and contaminants"
//   - evidenceResearch   (max 20)  "Clinical support behind ingredients"
//   - brandTrust         (max  5)  "Label clarity and independent testing"
//   - hasThirdPartyTesting → "Third-party tested" badge on Safety & Purity
//   - isTrustedManufacturer → "Trusted manufacturer" badge on Transparency
//   - heroScore          (0..100) → "Why this scored {N}" title
//   - mappedCoverage     (0..1)   → coverage line below pillars
//
// Sean's pre-approved v2 deliberate departures (from PGScoreBreakdownCard
// docs lines 155–169):
//   • 2-tone palette only (scoreExcellent / scoreGood) — never red on
//     diagnostic pillars. Quality signal ≠ safety signal.
//   • 0–10 normalized display per pillar (vs production's 25/30/20/5).
//     Users don't think in engineering scales.
//   • microExplanation + badges revealed on tap (vs production's
//     section_breakdown sub-score line parsing). Cleaner, less dense.
//
// Sean's rules (2026-05-15) — preserved verbatim:
//   • Preserve provider data (pillar scores, badges, hero score,
//     coverage) verbatim from product row + blob.
//   • Preserve pillar order, labels, microExplanation copy — verbatim
//     ports from production lines 115–172.
//   • Preserve coverage tier thresholds (≥0.7 / ≥0.3 / else) — already
//     done in PGScoreBreakdownCard's _PGCoverageLine (verbatim port).
//   • No invented language. No new tiers. No drift.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_score_breakdown_card.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Build the ScoreBreakdown section. Gated by
/// `shouldShowScoreBreakdown(isBlocked, isNotScored)` in the connected
/// screen — when blocked or NOT_SCORED, the section never renders.
Widget buildScoreBreakdownSection({
  required double? ingredientQuality,
  required double? safetyPurity,
  required double? evidenceResearch,
  required double? brandTrust,
  required bool hasThirdPartyTesting,
  required bool isTrustedManufacturer,
  required double? heroScore,
  required double? mappedCoverage,
  Map<String, dynamic>? sectionBreakdown,
}) {
  final pillars = <PGPillar>[
    // 1. Ingredient Quality — max 25
    PGPillar(
      label: 'Ingredient Quality',
      max: 25,
      score: ingredientQuality,
      microExplanation: 'Form, dosage, and bioavailability',
    ),

    // 2. Safety & Purity — max 30, optional Third-party tested badge
    PGPillar(
      label: 'Safety & Purity',
      max: 30,
      score: safetyPurity,
      microExplanation: 'Free from harmful ingredients and contaminants',
      badges: [
        if (hasThirdPartyTesting)
          const PGPillarBadge(
            icon: Icons.verified_outlined,
            label: 'Third-party tested',
            color: AppTheme.severitySafe,
          ),
      ],
    ),

    // 3. Evidence & Research — max 20
    PGPillar(
      label: 'Evidence & Research',
      max: 20,
      score: evidenceResearch,
      microExplanation: 'Clinical support behind ingredients',
    ),

    // 4. Transparency & Verification — max 5, optional Trusted Mfg badge.
    // Production renamed this pillar (was "Brand trust") in T14;
    // same engine field (`scoreBrandTrust`).
    PGPillar(
      label: 'Transparency & Verification',
      max: 5,
      score: brandTrust,
      microExplanation: 'Label clarity and independent testing',
      badges: [
        if (isTrustedManufacturer)
          const PGPillarBadge(
            icon: Icons.factory_outlined,
            label: 'Trusted manufacturer',
            color: AppTheme.severitySafe,
          ),
      ],
    ),
  ];

  return PGScoreBreakdownCard(
    pillars: pillars,
    mappedCoverage: mappedCoverage,
    heroScore: heroScore?.round(),
  );
}
