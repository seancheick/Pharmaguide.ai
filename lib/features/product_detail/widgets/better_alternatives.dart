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
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/fit_score/fit_display.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (category == null || category!.isEmpty || currentScore == null) {
      return const SizedBox.shrink();
    }

    final coreDb = ref.watch(coreDatabaseProvider);
    final minQuality80 = (currentScore! * 0.8).clamp(0.0, 80.0);

    return FutureBuilder<List<ProductsCoreData>>(
      future: coreDb.findAlternatives(
        category!,
        minQuality80,
        excludeDsldId: currentDsldId,
        limit: _maxAlternatives,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final alternatives = snapshot.data!;
        final resolved = AppColors.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Spec: V1 copy is exactly "Higher quality alternatives".
            // No subtitle in V1 — the title is self-explanatory and
            // adding a subtitle would push us toward editorialised
            // claims we don't yet have evidence for.
            Text(
              'Higher quality alternatives',
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
