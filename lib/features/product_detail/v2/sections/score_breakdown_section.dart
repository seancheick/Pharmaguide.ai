import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_score_breakdown_card.dart';
import 'package:pharmaguide/core/components/pg_trust_receipts_sheet.dart';
import 'package:pharmaguide/core/scoring/v4_pillars.dart';

/// Renders the optional explanation of a scored catalog product.
Widget buildScoreBreakdownSection({
  required double? heroScore,
  bool showTotal = true,
  String? qualityTier,
  Map<String, dynamic>? qualityPillarsV4,

  /// Optional deep-link callbacks keyed by v4 pillar key (`formulation`,
  /// `dose`, `evidence`, `transparency`, `verification`, `safety_hygiene`).
  /// Pillars without an entry stay link-free (no dead links).
  Map<String, VoidCallback>? onPillarTap,
}) {
  final parsed = readReconciledV4Pillars(qualityPillarsV4, heroScore);
  if (parsed.isEmpty) return const SizedBox.shrink();
  final pillars = _buildV4Pillars(parsed, onPillarTap: onPillarTap);

  return Builder(
    builder: (context) => PGScoreBreakdownCard(
      pillars: pillars,
      // Preserve the source value; the card owns the shared whole-number
      // consumer presentation used by the hero, headline, and total.
      heroScore: showTotal ? heroScore : null,
      qualityTier: qualityTier,
      onHowScoringWorks: () => showTrustReceiptsSheet(context),
    ),
  );
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
        displayState: p.displayState,
        facts: p.facts,
        actionLabel: onAction == null ? null : actionLabel,
        onAction: onAction,
      ),
    );
  }
  return out;
}
