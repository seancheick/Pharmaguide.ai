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
import 'package:pharmaguide/core/components/pg_trust_receipts_sheet.dart';
import 'package:pharmaguide/core/scoring/v4_pillars.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

// v4 pillar spec + parsing now live in `core/scoring/v4_pillars.dart`
// (shared with the Compare surface — single source of truth).

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

  /// Optional deep-link callbacks keyed by v4 pillar key (`formulation`,
  /// `dose`, `evidence`, `transparency`, `verification`, `safety_hygiene`).
  /// Pillars without an entry stay link-free (no dead links). v4 only —
  /// the v3 fallback never deep-links.
  Map<String, VoidCallback>? onPillarTap,
}) {
  // SHIP RULE: the v4 native-scale render requires ALL SIX pillars.
  // A partial blob (e.g. 4/6 entries) would draw a "= 62/100" sum line
  // under a 98.1 hero — visibly contradicting the score. Anything less
  // than 6/6 falls back to v3 (same rule the Compare surface applies).
  final parsedV4 = parseV4Pillars(qualityPillarsV4);
  final v4 = hasAllV4Pillars(parsedV4)
      ? _buildV4Pillars(
          parsedV4,
          hasThirdPartyTesting: hasThirdPartyTesting,
          isTrustedManufacturer: isTrustedManufacturer,
          onPillarTap: onPillarTap,
        )
      : const <PGPillar>[];

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

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PGScoreBreakdownCard(
        pillars: pillars,
        mappedCoverage: mappedCoverage,
        // v4: unrounded hero so the title matches the "= N/100" pillar-sum
        // line to the decimal. v3 fallback keeps the rounded int display.
        heroScore: v4.isNotEmpty ? heroScore : heroScore?.round(),
        nativeScale: v4.isNotEmpty,
      ),
      // Muted "How scoring works" link → Trust Receipts sheet. Wired at
      // the section level (NOT inside PGScoreBreakdownCard) so the card
      // stays a pure display component.
      const SizedBox(height: V2Spacing.space8),
      const _HowScoringWorksLink(),
    ],
  );
}

/// Quiet text link under the score breakdown card that opens the shared
/// Trust Receipts sheet (its "How scoring works" section explains the six
/// v4 pillars).
class _HowScoringWorksLink extends StatelessWidget {
  const _HowScoringWorksLink();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      onTap: () => showTrustReceiptsSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space8,
          vertical: V2Spacing.space4,
        ),
        child: Text(
          'How scoring works',
          style: V2Typography.caption(color: V2Colors.fgMuted),
        ),
      ),
    );
  }
}

/// Six v4 pillars from the pre-parsed (and 6/6-verified) pillar values.
List<PGPillar> _buildV4Pillars(
  List<V4PillarValue> parsed, {
  required bool hasThirdPartyTesting,
  required bool isTrustedManufacturer,
  Map<String, VoidCallback>? onPillarTap,
}) {
  final out = <PGPillar>[];
  for (final p in parsed) {
    // The verification pillar absorbs the v3 trust badges (third-party
    // testing / trusted manufacturer) — the closest v4 home for them.
    final badges = p.key == 'verification'
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
        label: p.label,
        max: p.max,
        score: p.score,
        microExplanation: p.reason,
        badges: badges,
        onTap: onPillarTap?[p.key],
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
