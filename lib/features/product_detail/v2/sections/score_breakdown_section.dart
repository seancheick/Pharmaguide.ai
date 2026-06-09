// ScoreBreakdown section adapter — DUAL-READER (v4 six-pillar / v3 four-section).
//
// v4 (export schema 2.0.0): when the detail blob carries `quality_pillars_v4`,
// render the SIX v4 pillars sourced from the blob —
//   Formulation /20 · Dose /20 · Evidence /20 · Transparency /15 ·
//   Verification /15 · Safety Hygiene /10
// each as score/max + a tap-revealed one-line `reason`. The hero is the v4
// /100 score (`score_100_equivalent` mirrors `quality_score_v4_100`).
//
// v3 fallback: when the blob has no `quality_pillars_v4` (a legacy bundle or a
// pre-v4 blob during the cutover window), render the original FOUR v3 pillars
// from the product row's section columns. This keeps the section correct on
// both schemas while the v4 catalog rolls out.
//
// ⚠️ The v3 section columns (`scoreIngredientQuality` etc.) are STILL emitted
// on a v4 build but are stale A/B/C/D math that contradicts the v4 headline
// (e.g. a ~73/100 four-section breakdown under a 98.1 hero). They are used
// ONLY for the v3 fallback — never when `quality_pillars_v4` is present.
//
// Suppressed (BLOCKED/UNSAFE/NOT_SCORED) products never reach this section —
// `shouldShowScoreBreakdown(isBlocked, isNotScored)` gates it off upstream.
//
// Sean's v2 rules preserved: 2-tone palette, score/max display,
// microExplanation revealed on tap, no invented language.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_score_breakdown_card.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';

/// v4 pillar key → (display label, max) in display order. Maxes match the
/// pipeline (`scripts/scoring_v4/config/quality_score.json`); the blob also
/// carries `max` per pillar, used in preference to this fallback.
const List<(String, String, int)> _v4PillarSpec = [
  ('formulation', 'Formulation', 20),
  ('dose', 'Dose', 20),
  ('evidence', 'Evidence', 20),
  ('transparency', 'Transparency', 15),
  ('verification', 'Verification', 15),
  ('safety_hygiene', 'Safety Hygiene', 10),
];

/// Build the ScoreBreakdown section. Gated by
/// `shouldShowScoreBreakdown(isBlocked, isNotScored)` in the connected
/// screen — when blocked or NOT_SCORED, the section never renders.
///
/// Pass `qualityPillarsV4` (the blob's `quality_pillars_v4` map) to render
/// the v4 six-pillar breakdown; when null/empty/malformed the adapter falls
/// back to the v3 four-pillar breakdown built from the row's section columns.
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
  Map<String, dynamic>? qualityPillarsV4,
}) {
  final v4 = qualityPillarsV4 == null
      ? const <PGPillar>[]
      : _buildV4Pillars(
          qualityPillarsV4,
          hasThirdPartyTesting: hasThirdPartyTesting,
          isTrustedManufacturer: isTrustedManufacturer,
        );

  final pillars = v4.isNotEmpty
      ? v4
      : _buildV3Pillars(
          ingredientQuality: ingredientQuality,
          safetyPurity: safetyPurity,
          evidenceResearch: evidenceResearch,
          brandTrust: brandTrust,
          hasThirdPartyTesting: hasThirdPartyTesting,
          isTrustedManufacturer: isTrustedManufacturer,
        );

  return PGScoreBreakdownCard(
    pillars: pillars,
    mappedCoverage: mappedCoverage,
    heroScore: heroScore?.round(),
  );
}

/// Six v4 pillars from the blob's `quality_pillars_v4`. Returns `[]` when the
/// map is missing/malformed so the caller can fall back to the v3 pillars.
List<PGPillar> _buildV4Pillars(
  Map<String, dynamic> pillarsBlob, {
  required bool hasThirdPartyTesting,
  required bool isTrustedManufacturer,
}) {
  final out = <PGPillar>[];
  for (final (key, label, fallbackMax) in _v4PillarSpec) {
    final raw = pillarsBlob[key];
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final score = (m['score'] as num?)?.toDouble();
    final max = (m['max'] as num?)?.toInt() ?? fallbackMax;
    final reason = (m['reason'] as String?)?.trim();

    // The verification pillar absorbs the v3 trust badges (third-party
    // testing / trusted manufacturer) — the closest v4 home for them.
    final badges = key == 'verification'
        ? <PGPillarBadge>[
            if (hasThirdPartyTesting)
              const PGPillarBadge(
                icon: Icons.verified_outlined,
                label: 'Third-party tested',
                color: V2Colors.safe,
              ),
            if (isTrustedManufacturer)
              const PGPillarBadge(
                icon: Icons.factory_outlined,
                label: 'Trusted manufacturer',
                color: V2Colors.safe,
              ),
          ]
        : const <PGPillarBadge>[];

    out.add(
      PGPillar(
        label: label,
        max: max,
        score: score,
        microExplanation: (reason != null && reason.isNotEmpty) ? reason : null,
        badges: badges,
      ),
    );
  }
  return out;
}

/// Legacy v3 four-pillar breakdown (Ingredient Quality / Safety & Purity /
/// Evidence & Research / Transparency & Verification) from the row's section
/// columns. Verbatim port of the original adapter.
List<PGPillar> _buildV3Pillars({
  required double? ingredientQuality,
  required double? safetyPurity,
  required double? evidenceResearch,
  required double? brandTrust,
  required bool hasThirdPartyTesting,
  required bool isTrustedManufacturer,
}) {
  return <PGPillar>[
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
            color: V2Colors.safe,
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
            color: V2Colors.safe,
          ),
      ],
    ),
  ];
}
