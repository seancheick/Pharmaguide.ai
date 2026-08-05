// Compare screen — two products side by side.
//
// Calm by design: numbers are presented, never judged. No "winner"
// badge, no "better" language. Pillar data comes from the SAME
// blob/`quality_pillars_v4` path the score breakdown uses (shared
// parser in `core/scoring/v4_pillars.dart`); tier colors come from the
// existing ScoreTier mapping via PGScoreLine; coverage hedging uses the
// same mappedCoverage <0.3 floor as the stack safety banner.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_compare_pillar_row.dart';
import 'package:pharmaguide/core/components/pg_score_breakdown_card.dart'
    show PGScoreBreakdownCard;
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/core/scoring/v4_pillars.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/features/compare/compare_providers.dart';
import 'package:pharmaguide/features/product_detail/v2/gating.dart';

// TODO(compare): personalized FitScore chips per product. The existing
// fit surface (PGPersonalFitCard + fitScoreForProductProvider) is a
// full card, not a reusable chip — adding chips here would mean new
// plumbing, so it's deferred per the cheap-version scope.

/// Side-by-side comparison of two catalog products by dsldId.
class CompareScreen extends ConsumerWidget {
  final String dsldIdA;
  final String dsldIdB;

  const CompareScreen({
    super.key,
    required this.dsldIdA,
    required this.dsldIdB,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryA = ref.watch(compareEntryProvider(dsldIdA));
    final entryB = ref.watch(compareEntryProvider(dsldIdB));

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.v2.fg),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(Routes.home);
            }
          },
        ),
        title: Text(
          'Compare',
          style: V2Typography.titleSm(color: context.v2.fg),
        ),
        centerTitle: false,
      ),
      body: (entryA.isLoading || entryB.isLoading)
          ? Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: context.v2.accent,
              ),
            )
          // A provider ERROR is not the same as a missing product — the
          // catalog message would be a false claim ("isn't in the verified
          // catalog") when the lookup itself failed. Calm, honest copy.
          : (entryA.hasError || entryB.hasError)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(V2Spacing.space24),
                child: Text(
                  'This comparison couldn\'t load right now.',
                  key: const Key('compare-load-error'),
                  style: V2Typography.bodySm(color: context.v2.fgMuted),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _CompareBody(
              a:
                  entryA.asData?.value ??
                  const CompareEntry(
                    product: null,
                    blob: null,
                    blobFailed: true,
                  ),
              b:
                  entryB.asData?.value ??
                  const CompareEntry(
                    product: null,
                    blob: null,
                    blobFailed: true,
                  ),
            ),
    );
  }
}

class _CompareBody extends StatelessWidget {
  final CompareEntry a;
  final CompareEntry b;
  const _CompareBody({required this.a, required this.b});

  @override
  Widget build(BuildContext context) {
    if (a.product == null || b.product == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(V2Spacing.space24),
          child: Text(
            'One of these products isn\'t in the verified catalog on '
            'this device.',
            style: V2Typography.bodySm(color: context.v2.fgMuted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final productA = a.product!;
    final productB = b.product!;

    final blockedA = productIsBlocked(productA);
    final blockedB = productIsBlocked(productB);
    final notScoredA = productIsNotScored(productA);
    final notScoredB = productIsNotScored(productB);
    final scorableA = !blockedA && !notScoredA;
    final scorableB = !blockedB && !notScoredB;

    final pillarsA = scorableA
        ? parseV4Pillars(a.qualityPillarsV4)
        : const <V4PillarValue>[];
    final pillarsB = scorableB
        ? parseV4Pillars(b.qualityPillarsV4)
        : const <V4PillarValue>[];
    // SHARED SHIP RULE (same as the score-breakdown adapter): pillar rows
    // require ALL SIX parsed pillars on BOTH sides — a partial blob would
    // pair mismatched scales and imply a complete comparison that isn't.
    final showPillars = hasAllV4Pillars(pillarsA) && hasAllV4Pillars(pillarsB);

    // A scorable product whose blob failed to load (offline) gets the
    // calm connection hedge instead of pillar rows.
    final blobMissing =
        (scorableA && !hasAllV4Pillars(pillarsA)) ||
        (scorableB && !hasAllV4Pillars(pillarsB));
    final needsConnection = blobMissing && (a.blobFailed || b.blobFailed);

    final categoryA = (productA.primaryCategory ?? '').trim();
    final categoryB = (productB.primaryCategory ?? '').trim();
    final categoriesDiffer =
        categoryA.isNotEmpty &&
        categoryB.isNotEmpty &&
        categoryA.toLowerCase() != categoryB.toLowerCase();

    final lowCoverage =
        isLowCoverage(productA.mappedCoverage) ||
        isLowCoverage(productB.mappedCoverage);

    final delta = _largestPillarGap(
      pillarsA: pillarsA,
      pillarsB: pillarsB,
      scoreA: scorableA ? productA.qualityScoreV4100 : null,
      scoreB: scorableB ? productB.qualityScoreV4100 : null,
    );

    return ListView(
      padding: const EdgeInsets.all(V2Spacing.space16),
      children: [
        if (categoriesDiffer) ...[
          Text(
            'These are different product types — pillar comparisons are '
            'most meaningful within a category.',
            style: V2Typography.caption(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ProductHeader(
                product: productA,
                isBlocked: blockedA,
                isNotScored: notScoredA,
              ),
            ),
            const SizedBox(width: V2Spacing.space16),
            Expanded(
              child: _ProductHeader(
                product: productB,
                isBlocked: blockedB,
                isNotScored: notScoredB,
              ),
            ),
          ],
        ),
        const SizedBox(height: V2Spacing.space16),
        if (showPillars)
          Container(
            padding: const EdgeInsets.all(V2Spacing.space16),
            decoration: BoxDecoration(
              color: context.v2.surface,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: context.v2.outline),
              boxShadow: V2Shadows.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pillar by pillar',
                  style: V2Typography.titleSm(color: context.v2.fg),
                ),
                const SizedBox(height: V2Spacing.space4),
                Text(
                  'Six pillars, out of 100 — they add up to each score.',
                  style: V2Typography.caption(color: context.v2.fgMuted),
                ),
                const SizedBox(height: V2Spacing.space16),
                for (var i = 0; i < pillarsA.length; i++) ...[
                  if (i > 0) const SizedBox(height: V2Spacing.space12),
                  PGComparePillarRow(
                    label: pillarsA[i].label,
                    maxA: pillarsA[i].max,
                    // Each side renders against its OWN max — never A's.
                    // 6/6 on both sides is guaranteed by showPillars, so
                    // the key lookup always resolves.
                    maxB:
                        _pillarForKey(pillarsB, pillarsA[i].key)?.max ??
                        pillarsA[i].max,
                    scoreA: pillarsA[i].score,
                    scoreB: _pillarForKey(pillarsB, pillarsA[i].key)?.score,
                  ),
                ],
                if (delta != null) ...[
                  const SizedBox(height: V2Spacing.space12),
                  Divider(color: context.v2.outline, height: 1, thickness: 0.5),
                  const SizedBox(height: V2Spacing.space8),
                  Text(
                    delta,
                    key: const Key('compare-delta-callout'),
                    style: V2Typography.caption(color: context.v2.fgMuted),
                  ),
                ],
              ],
            ),
          )
        else if (needsConnection) ...[
          Text(
            'Detailed pillar comparison needs a connection.',
            key: const Key('compare-connection-hedge'),
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
        ],
        if (lowCoverage) ...[
          const SizedBox(height: V2Spacing.space12),
          Text(
            coverageHedge('results may be incomplete'),
            key: const Key('compare-coverage-hedge'),
            style: V2Typography.caption(color: context.v2.fgMuted),
          ),
        ],
      ],
    );
  }

  static V4PillarValue? _pillarForKey(List<V4PillarValue> pillars, String key) {
    for (final p in pillars) {
      if (p.key == key) return p;
    }
    return null;
  }

  /// The one calm delta line: only when both hero scores exist and
  /// differ by ≥ 3, name the pillar with the largest absolute gap.
  ///
  /// Honesty rule: "Most of the difference is X" is only claimed when
  /// that pillar's gap actually accounts for at least half the total
  /// hero delta — otherwise the calmer, strictly-true "The largest
  /// pillar gap is X" framing is used.
  static String? _largestPillarGap({
    required List<V4PillarValue> pillarsA,
    required List<V4PillarValue> pillarsB,
    required double? scoreA,
    required double? scoreB,
  }) {
    if (scoreA == null || scoreB == null) return null;
    if ((scoreA - scoreB).abs() < 3) return null;
    if (pillarsA.isEmpty || pillarsB.isEmpty) return null;

    String? bestLabel;
    double? bestA;
    double? bestB;
    var bestGap = 0.0;
    for (final pa in pillarsA) {
      final sa = pa.score;
      final sb = _pillarForKey(pillarsB, pa.key)?.score;
      if (sa == null || sb == null) continue;
      final gap = (sa - sb).abs();
      if (gap > bestGap) {
        bestGap = gap;
        bestLabel = pa.label;
        bestA = sa;
        bestB = sb;
      }
    }
    if (bestLabel == null || bestGap == 0.0) return null;
    final fa = PGScoreBreakdownCard.fmtScore(bestA!);
    final fb = PGScoreBreakdownCard.fmtScore(bestB!);
    final totalDelta = (scoreA - scoreB).abs();
    return bestGap >= totalDelta / 2
        ? 'Most of the difference is $bestLabel: $fa vs $fb.'
        : 'The largest pillar gap is $bestLabel: $fa vs $fb.';
  }
}

/// One product's header column: brand, name, and either the tier-colored
/// score line (rounded display, consistent with the hero's PGScoreLine
/// usage) or its calm verdict status when blocked / not scored.
class _ProductHeader extends StatelessWidget {
  final ProductsCoreData product;
  final bool isBlocked;
  final bool isNotScored;

  const _ProductHeader({
    required this.product,
    required this.isBlocked,
    required this.isNotScored,
  });

  @override
  Widget build(BuildContext context) {
    final brand = product.brandName ?? '';
    final name = product.productName;
    final score = product.qualityScoreV4100?.round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (brand.isNotEmpty) ...[
          Text(
            brand,
            style: V2Typography.caption(color: context.v2.fgMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: V2Spacing.space4),
        ],
        Text(
          name,
          style: V2Typography.bodyMedium(color: context.v2.fg),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: V2Spacing.space8),
        if (isBlocked)
          Text(
            'Not recommended — see product page',
            style: V2Typography.caption(color: context.v2.fgMuted),
          )
        else if (isNotScored || score == null)
          Text(
            'Not scored yet',
            style: V2Typography.caption(color: context.v2.fgMuted),
          )
        else
          PGScoreLine(
            score: score,
            compact: true,
            confidence: product.v4Confidence,
          ),
      ],
    );
  }
}
