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

  final pillars = _buildV4Pillars(
    parsedV4,
    mappedCoverage: mappedCoverage,
    sectionBreakdown: sectionBreakdown,
    onPillarTap: onPillarTap,
  );

  return Builder(
    builder: (context) => Semantics(
      container: true,
      label: _evidenceScopeSemanticsLabel(
        pillars,
        mappedCoverage: mappedCoverage,
        sectionBreakdown: sectionBreakdown,
      ),
      child: PGScoreBreakdownCard(
        pillars: pillars,
        mappedCoverage: mappedCoverage,
        // Preserve the source value; the card owns the shared whole-number
        // consumer presentation used by the hero, headline, and total.
        heroScore: heroScore,
        onHowScoringWorks: () => showTrustReceiptsSheet(context),
      ),
    ),
  );
}

/// Quiet fallback link that opens the shared PG Score explanation sheet.
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
          'How PG Score works',
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
  double? mappedCoverage,
  Map<String, dynamic>? sectionBreakdown,
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
        reason: p.key == 'evidence'
            ? _formulaEvidenceReason(p.reason)
            : p.reason,
        facts: p.key == 'evidence'
            ? _evidenceScopeFacts(
                p.facts,
                mappedCoverage: mappedCoverage,
                sectionBreakdown: sectionBreakdown,
              )
            : p.facts,
        actionLabel: onAction == null ? null : actionLabel,
        onAction: onAction,
      ),
    );
  }
  return out;
}

/// Evidence is an aggregate pillar, while the clinical-evidence section may
/// describe one strongly supported ingredient. Keep those scopes visibly
/// separate without changing the pipeline-authored score or reason.
List<V4PillarFact> _evidenceScopeFacts(
  List<V4PillarFact> pipelineFacts, {
  required double? mappedCoverage,
  required Map<String, dynamic>? sectionBreakdown,
}) {
  final facts = <V4PillarFact>[];

  final metadataParts = <String>[];
  if (mappedCoverage != null && mappedCoverage.isFinite) {
    final percent = (mappedCoverage.clamp(0.0, 1.0) * 100).round();
    metadataParts.add('$percent% analysis coverage');
  }

  final evidenceBreakdown = _asStringMap(
    sectionBreakdown?['evidence_research'],
  );
  final sourceCount = _nonNegativeInt(evidenceBreakdown?['source_count']);
  if (sourceCount != null) {
    metadataParts.add(
      '$sourceCount evidence ${sourceCount == 1 ? 'source' : 'sources'}',
    );
  }

  final matchedEntries = _nonNegativeInt(evidenceBreakdown?['matched_entries']);
  if (matchedEntries != null) {
    metadataParts.add(
      '$matchedEntries matched evidence '
      '${matchedEntries == 1 ? 'record' : 'records'}',
    );
  }
  if (metadataParts.isNotEmpty) {
    facts.add(
      V4PillarFact(
        id: 'ui_evidence_analysis_metadata',
        label: 'Analysis metadata',
        valueDisplay: metadataParts.join(' · '),
      ),
    );
  }

  facts.addAll(pipelineFacts);
  return facts;
}

String _formulaEvidenceReason(String? pipelineReason) {
  const scope =
      'Formula-wide evidence depends on coverage, not one strong ingredient.';
  final reason = pipelineReason?.trim() ?? '';
  return reason.isEmpty ? scope : '$scope $reason';
}

String _evidenceScopeSemanticsLabel(
  List<PGPillar> pillars, {
  required double? mappedCoverage,
  required Map<String, dynamic>? sectionBreakdown,
}) {
  final evidence = pillars.where((pillar) => pillar.label == 'Evidence').first;
  final score = evidence.score == null
      ? 'score unavailable'
      : '${PGScoreBreakdownCard.fmtScore(evidence.score!)} out of ${evidence.max}';
  final parts = <String>[
    'Evidence pillar, $score',
    'Formula-wide, coverage-dependent',
    'Strong evidence for one ingredient does not represent the whole formula',
  ];

  if (mappedCoverage != null && mappedCoverage.isFinite) {
    final percent = (mappedCoverage.clamp(0.0, 1.0) * 100).round();
    parts.add('Analysis coverage, $percent percent mapped');
  }

  final evidenceBreakdown = _asStringMap(
    sectionBreakdown?['evidence_research'],
  );
  final sourceCount = _nonNegativeInt(evidenceBreakdown?['source_count']);
  if (sourceCount != null) {
    parts.add(
      '$sourceCount evidence ${sourceCount == 1 ? 'source' : 'sources'}',
    );
  }
  final matchedEntries = _nonNegativeInt(evidenceBreakdown?['matched_entries']);
  if (matchedEntries != null) {
    parts.add(
      '$matchedEntries matched evidence '
      '${matchedEntries == 1 ? 'record' : 'records'}',
    );
  }

  return '${parts.join('. ')}.';
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

int? _nonNegativeInt(Object? value) {
  final parsed = switch (value) {
    final num number
        when number.isFinite && number == number.truncateToDouble() =>
      number.toInt(),
    final String text => int.tryParse(text.trim()),
    _ => null,
  };
  if (parsed == null || parsed < 0) return null;
  return parsed;
}
