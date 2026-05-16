// Better Alternatives section (Section 11) — V1 non-personalized.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.12.
//
// Conditional render: surface 2-3 higher-quality alternatives in the
// same category when the current product is blocked, low quality, or
// the user's fit math came back limited / not recommended. V1 copy
// is exactly **"Higher quality alternatives"** and the section
// intentionally does NOT show a per-row "+N fit" delta — personalized
// fit deltas are deferred until the math is more battle-tested.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_shimmer_box.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';
import 'package:pharmaguide/services/recommendations/better_alternatives_ranker.dart';

/// Maximum number of alternatives surfaced — spec calls for 2-3.
/// More than that turns the section into a category browser; the
/// goal here is "show the user a clearly-better swap", not exhaustive
/// shopping.
const int _maxAlternatives = 3;

/// Quality threshold (100-scale) below which the section fires
/// regardless of fit state. Spec: "low quality (<60)".
const double _lowQualityThreshold = 60.0;

/// Pure helper — should the Better Alternatives section render for
/// this product + user state?
///
/// V1 trigger conditions per spec:
///   - Product is blocked (avoid / contraindicated severity)
///   - score100 < 60 (low product quality)
///   - FitDisplay is FitLimitedFit or FitNotRecommended
///
/// Hidden when:
///   - Product is unscored (no signal to act on)
///   - score100 ≥ 60 AND fit is FitStrongMatch / FitGoodMatch /
///     FitHidden / FitIncomplete (FitHidden is already covered by
///     isBlocked, FitIncomplete means we lack profile to judge fit)
bool shouldShowBetterAlternatives({
  required bool isBlocked,
  required bool isNotScored,
  required double? score100,
  required FitDisplay? fitDisplay,
}) {
  if (isBlocked) return true;
  if (isNotScored || score100 == null) return false;
  if (score100 < _lowQualityThreshold) return true;
  if (fitDisplay is FitLimitedFit || fitDisplay is FitNotRecommended) {
    return true;
  }
  return false;
}

/// Section 11 widget. Caller is responsible for the trigger gate via
/// [shouldShowBetterAlternatives]; this widget then handles the
/// async data load + empty-state gate inside its FutureBuilder.
class BetterAlternativesSection extends ConsumerWidget {
  final String currentDsldId;
  final String? category;
  final double? currentScore;

  const BetterAlternativesSection({
    super.key,
    required this.currentDsldId,
    this.category,
    this.currentScore,
  });

  /// Phase 11.7L.F — fetch the current product, build a wider
  /// candidate pool (on-market + strictly higher score + same
  /// category OR supplement_type), then hand the pool to the pure
  /// `BetterAlternativesRanker` for the 4-tier tiebreaker chain.
  ///
  /// Returns `[]` when:
  ///   * the current product isn't in the DB (no signal to act on)
  ///   * the SQL pool is empty after hard filters
  ///   * every candidate fails the audience + sport-carveout walls
  Future<List<ProductsCoreData>> _loadRanked(CoreDatabase coreDb) async {
    final current = await coreDb.findById(currentDsldId);
    if (current == null) return const [];
    final pool = await coreDb.fetchBetterAlternativesPool(current);
    if (pool.isEmpty) return const [];
    return rankAlternatives(
      current: current,
      candidates: pool,
      limit: _maxAlternatives,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phase 11.7L.F follow-up (Sean 2026-05-16): do not gate on
    // `category` or `currentScore` here. The pool query already
    // handles category-or-supplement_type matching, and the ranker
    // handles the score comparison (including the no-score-on-
    // blocked-product case for items like Vinpocetine, which has
    // `primary_category=''` and `score_quality_80=NULL`).
    final coreDb = ref.watch(coreDatabaseProvider);

    return FutureBuilder<List<ProductsCoreData>>(
      future: _loadRanked(coreDb),
      builder: (context, snapshot) {
        // Loading skeleton — keeps the scroll anchor stable so the
        // sticky CTA "Better alternatives" scroll target lands here
        // instead of jumping past an empty slot.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _LoadingSkeleton();
        }
        if (snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final alternatives = snapshot.data!;
        final resolved = AppColors.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title updated 2026-05-16 (Sean): the new ranker mixes
            // strict-quality picks with intent/family/audience
            // matches, so "Similar higher-quality options" reflects
            // what we actually return better than the old
            // category-only "Higher quality alternatives".
            Text(
              'Similar higher-quality options',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.15,
                color: resolved.textPrimary,
              ),
            ),
            const SizedBox(height: AppTheme.space12),
            ...alternatives.map(
              (product) => _AlternativeCard(product: product),
            ),
          ],
        );
      },
    );
  }
}

/// Cream skeleton placeholder shown while the ranked pool resolves.
/// Same vertical rhythm as the rendered section so the scroll anchor
/// doesn't shift when data lands. Two rows is enough to signal
/// "stuff is coming" without claiming a specific count.
class _LoadingSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PGShimmerBox(width: 220, height: 18, radius: 4),
        SizedBox(height: AppTheme.space12),
        PGShimmerCard(height: 72),
        SizedBox(height: AppTheme.space8),
        PGShimmerCard(height: 72),
      ],
    );
  }
}

class _AlternativeCard extends StatelessWidget {
  final ProductsCoreData product;

  const _AlternativeCard({required this.product});

  Color _scoreColor(double? score, BuildContext context) {
    if (score == null) return AppColors.of(context).textSecondary;
    if (score >= 85) return AppColors.scoreExceptional;
    if (score >= 70) return AppColors.scoreExcellent;
    if (score >= 55) return AppColors.scoreGood;
    if (score >= 40) return AppColors.scoreFair;
    if (score >= 25) return AppColors.scoreBelowAvg;
    return AppColors.scoreLow;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = AppColors.of(context);
    final score = product.score100Equivalent;
    final color = _scoreColor(score, context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PGCard(
        padding: const EdgeInsets.all(AppTheme.space12),
        onTap: () => context.push('/product/${product.dsldId}'),
        child: Row(
          children: [
            // Score badge — the only badge per row in V1; no per-row
            // "+N fit" delta. Personalized deltas are deferred until
            // the fit math has proven itself across more profiles.
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withAlpha(20),
                border: Border.all(color: color.withAlpha(80)),
              ),
              alignment: Alignment.center,
              child: Text(
                score?.toStringAsFixed(0) ?? '--',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: AppTheme.space12),
            // Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: resolved.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.brandName != null &&
                      product.brandName!.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.space2),
                    Text(
                      product.brandName!,
                      style: TextStyle(
                        fontSize: 12,
                        color: resolved.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: resolved.textSecondary),
          ],
        ),
      ),
    );
  }
}
