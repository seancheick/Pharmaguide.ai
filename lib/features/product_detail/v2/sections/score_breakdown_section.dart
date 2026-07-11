// ScoreBreakdown section adapter — v4 six-pillar reader.
//
// v4 (export schema 2.0.0): when the detail blob carries `quality_pillars_v4`,
// render the SIX v4 pillars sourced from the blob —
//   Formulation /20 · Dose /20 · Evidence /20 · Transparency /15 ·
//   Testing & Brand /15 · Safety Hygiene /10
// each as score/max + a tap-revealed one-line `reason`. The hero is the v4
// /100 score (`score_100_equivalent` mirrors `quality_score_v4_100`).
//
// Missing or partial v4 pillar blobs render an unavailable state. The app is
// now clean-cut v4: stale v3 A/B/C/D section columns must never explain a v4
// headline score.
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
/// the v4 six-pillar breakdown. When null/empty/malformed, the adapter shows
/// an unavailable state rather than stale v3 score math.
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
  /// Pillars without an entry stay link-free (no dead links).
  Map<String, VoidCallback>? onPillarTap,
}) {
  // SHIP RULE: the v4 native-scale render requires ALL SIX pillars.
  // A partial blob (e.g. 4/6 entries) would draw a "= 62/100" sum line
  // under a 98.1 hero — visibly contradicting the score. Anything less
  // than 6/6 renders an unavailable state.
  final parsedV4 = parseV4Pillars(qualityPillarsV4);
  if (!hasAllV4Pillars(parsedV4)) {
    return const _ScoreBreakdownUnavailable();
  }

  final pillars = _buildV4Pillars(parsedV4, onPillarTap: onPillarTap);

  return Builder(
    builder: (context) => PGScoreBreakdownCard(
      pillars: pillars,
      mappedCoverage: mappedCoverage,
      // Unrounded hero so the title matches the "= N/100" pillar-sum line.
      heroScore: heroScore,
      onHowScoringWorks: () => showTrustReceiptsSheet(context),
    ),
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

class _ScoreBreakdownUnavailable extends StatelessWidget {
  const _ScoreBreakdownUnavailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Score breakdown unavailable',
            style: V2Typography.titleSm(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space4),
          Text(
            'This catalog entry is missing the v4 pillar details needed to '
            'explain the score.',
            style: V2Typography.bodySm(color: V2Colors.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space8),
          const _HowScoringWorksLink(),
        ],
      ),
    );
  }
}

/// Six v4 pillars from the pre-parsed (and 6/6-verified) pillar values.
List<PGPillar> _buildV4Pillars(
  List<V4PillarValue> parsed, {
  Map<String, VoidCallback>? onPillarTap,
}) {
  final out = <PGPillar>[];
  for (final p in parsed) {
    final actionLabel = kV4PillarActionLabels[p.key];
    final onAction = actionLabel == null ? null : onPillarTap?[p.key];

    out.add(
      PGPillar(
        label: p.label,
        max: p.max,
        score: p.score,
        reason: p.reason,
        facts: p.facts,
        actionLabel: onAction == null ? null : actionLabel,
        onAction: onAction,
      ),
    );
  }
  return out;
}
