// ScoreBreakdown section adapter — v4 six-pillar reader.
//
// v4 (export schema 2.0.0): when the detail blob carries `quality_pillars_v4`,
// render the SIX v4 pillars sourced from the blob —
//   Formulation /20 · Dose /20 · Evidence /20 · Transparency /15 ·
//   Testing & Brand /15 · Formula & quality checks /10
// each as score/max + a tap-revealed one-line `reason`. The hero is the v4
// /100 score (`score_100_equivalent` mirrors `quality_score_v4_100`).
//
// Missing or partial v4 pillar blobs suppress this optional section. The app
// is clean-cut v4: stale v3 A/B/C/D section columns must never explain a v4
// headline score, and catalog-maintenance states must never reach consumers.
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
import 'package:pharmaguide/core/utils/num_parse.dart';

// v4 pillar spec + parsing now live in `core/scoring/v4_pillars.dart`
// (shared with the Compare surface — single source of truth).

/// Build the ScoreBreakdown section. Gated by
/// `shouldShowScoreBreakdown(isBlocked, isNotScored)` in the connected
/// screen — when blocked or NOT_SCORED, the section never renders.
///
/// Pass `qualityPillarsV4` (the blob's `quality_pillars_v4` map) to render
/// the v4 six-pillar breakdown. Null/empty/malformed data is suppressed rather
/// than exposing catalog diagnostics or stale v3 score math.
Widget buildScoreBreakdownSection({
  required double? ingredientQuality,
  required double? safetyPurity,
  required double? evidenceResearch,
  required double? brandTrust,
  required double? heroScore,
  required double? mappedCoverage,
  Map<String, dynamic>? sectionBreakdown,
  Map<String, dynamic>? qualityPillarsV4,
  Map<String, dynamic>? qualityScoreCapV4,

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
    return const SizedBox.shrink();
  }

  var adjustment = _categoryAdjustment(qualityScoreCapV4);
  var displayValues = parsedV4;
  if (adjustment != null) {
    final restored = _restorePreCapPillars(parsedV4, qualityPillarsV4);
    final restoredTotal = restored.fold<double>(
      0,
      (total, pillar) => total + (pillar.score ?? 0),
    );
    final declaredBefore = adjustment.finalScore - adjustment.delta;
    if ((restoredTotal - declaredBefore).abs() <= 0.05) {
      displayValues = restored;
    } else {
      // Never show arithmetic the shipped pillar evidence cannot reproduce.
      adjustment = null;
    }
  }
  final pillars = _buildV4Pillars(displayValues, onPillarTap: onPillarTap);

  return Builder(
    builder: (context) => PGScoreBreakdownCard(
      pillars: pillars,
      // Preserve the source value; the card owns the shared whole-number
      // consumer presentation used by the hero, headline, and total.
      heroScore: heroScore,
      adjustment: adjustment,
      onHowScoringWorks: () => showTrustReceiptsSheet(context),
    ),
  );
}

PGScoreAdjustment? _categoryAdjustment(Map<String, dynamic>? cap) {
  if (cap?['applied'] != true) return null;
  final before = asFiniteDouble(cap?['score_before_cap']);
  final after = asFiniteDouble(cap?['score_after_cap']);
  if (before == null || after == null || before <= after) return null;
  return PGScoreAdjustment(
    label: 'Category calibration',
    delta: after - before,
    finalScore: after,
  );
}

List<V4PillarValue> _restorePreCapPillars(
  List<V4PillarValue> parsed,
  Map<String, dynamic>? pillarsBlob,
) {
  return parsed
      .map((pillar) {
        final rawPillar = pillarsBlob?[pillar.key];
        final rawComponents = rawPillar is Map ? rawPillar['components'] : null;
        final scoreBeforeCap = rawComponents is Map
            ? asFiniteDouble(rawComponents['score_before_public_cap'])
            : null;
        return V4PillarValue(
          key: pillar.key,
          label: pillar.label,
          max: pillar.max,
          score: scoreBeforeCap ?? pillar.score,
          reason: pillar.reason,
          facts: pillar.facts,
        );
      })
      .toList(growable: false);
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
        reason: switch (p.key) {
          'evidence' => _formulaEvidenceReason(p.reason),
          'safety_hygiene' => _formulaQualityChecksReason(p.reason),
          _ => p.reason,
        },
        facts: p.facts,
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
String _formulaEvidenceReason(String? pipelineReason) {
  const scope =
      'Formula-wide evidence reflects the full ingredient profile, not one '
      'strongly supported ingredient.';
  final reason = pipelineReason?.trim() ?? '';
  return reason.isEmpty ? scope : '$scope $reason';
}

String _formulaQualityChecksReason(String? pipelineReason) {
  final reason = pipelineReason?.trim() ?? '';
  return reason.isEmpty
      ? kFormulaQualityChecksScope
      : '$kFormulaQualityChecksScope $reason';
}
