// Phase 11.7e — BetterAlternatives section adapter (S16).
//
// Better Alternatives v2 section.
//
// Gate rules (verbatim port via `shouldShowBetterAlternatives`):
//   • product is blocked → ALWAYS render
//   • product unscored → hide
//   • score < 60 → render
//   • incomplete profile + Acceptable product → generic quality options
//
// Data flow:
//   1. Check the product-quality gate → SizedBox.shrink if not applicable
//   3. Load the relevance-first SQL pool, then apply the pure ranker
//   4. Map ProductsCoreData → PGAlternative
//   5. Each tap → context.push('/product/<dsldId>')
//
// Notes:
//   • Sticky CTA in the connected screen scrolls to this section's
//     anchor via `_anchors.alternativesKey` (kept on the wrapping
//     widget in the connected screen).
//   • Max 3 alternatives (PGBetterAlternatives convention).
//   • Empty result list → SizedBox.shrink (no fallback copy).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_better_alternatives.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/product_image.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/recommendations/better_alternatives_ranker.dart';

const double _lowQualityThreshold = 60.0;

/// Pure helper — should the Better Alternatives section render for this
/// product + user state?
bool shouldShowBetterAlternatives({
  required bool isBlocked,
  required bool isNotScored,
  required double? score100,
  required bool profileIncomplete,
  String? qualityTier,
}) {
  if (isBlocked) return true;
  if (isNotScored || score100 == null) return false;
  if (score100 < _lowQualityThreshold) return true;
  // S4 — incomplete profile: still surface *generic* higher-quality
  // options for the shared Acceptable quality tier. Do not invent a local score
  // cutoff or use fit status (either would drift from the score contract).
  if (profileIncomplete) {
    return catalogTier(
          qualityTier: qualityTier,
          legacyScore: score100.round(),
        ) ==
        ScoreTier.acceptable;
  }
  return false;
}

/// Quality-only alternatives section. Profile goals can break ties, but this
/// surface never claims candidate-level safety or personal fit.
class BetterAlternativesSection extends ConsumerWidget {
  final String currentDsldId;
  final bool isBlocked;
  final bool isNotScored;
  final double? score100;
  final String? qualityTier;
  final bool profileIncomplete;

  /// Max alternatives to display (matches PGBetterAlternatives convention).
  final int maxAlternatives;

  const BetterAlternativesSection({
    super.key,
    required this.currentDsldId,
    required this.isBlocked,
    required this.isNotScored,
    required this.score100,
    required this.profileIncomplete,
    this.qualityTier,
    this.maxAlternatives = 3,
  });

  /// Fetches the current product, builds a wider candidate pool
  /// (on-market + strictly higher score + intent/family channels), then
  /// hands it to `BetterAlternativesRanker` for the final relevance and
  /// tiebreaker pass.
  Future<List<ProductsCoreData>> _loadRanked(
    CoreDatabase coreDb, {
    Set<String>? userGoals,
  }) async {
    final current = await coreDb.findById(currentDsldId);
    if (current == null) return const [];
    final pool = await coreDb.fetchBetterAlternativesPool(current);
    if (pool.isEmpty) return const [];
    return rankAlternatives(
      current: current,
      candidates: pool,
      userGoals: userGoals,
      limit: maxAlternatives,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!shouldShowBetterAlternatives(
      isBlocked: isBlocked,
      isNotScored: isNotScored,
      score100: score100,
      profileIncomplete: profileIncomplete,
      qualityTier: qualityTier,
    )) {
      return const SizedBox.shrink();
    }

    // Phase 11.7L.F follow-up (Sean 2026-05-16): no category gate
    // here. `fetchBetterAlternativesPool` handles category OR
    // supplement_type matching, and Vinpocetine-style blocked
    // products have empty category but a usable supplement_type.

    final coreDb = ref.watch(coreDatabaseProvider);
    // Personalize tiebreakers when the profile has goals (sentinel-stripped).
    final userGoals = ref.watch(profileProvider).goalsForEvaluator.toSet();

    return FutureBuilder<List<ProductsCoreData>>(
      future: _loadRanked(
        coreDb,
        userGoals: userGoals.isEmpty ? null : userGoals,
      ),
      builder: (context, snapshot) {
        // Loading skeleton — keeps the sticky-CTA scroll anchor
        // landing on a real surface, not an empty slot mid-fetch.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const PGBetterAlternativesSkeleton();
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return isBlocked
              ? const _BlockedAlternativesEmpty()
              : const SizedBox.shrink();
        }
        final alternatives = snapshot.data!;
        final mapped = alternatives
            .where((p) => p.qualityScoreV4100 != null)
            .map((p) {
              final score = p.qualityScoreV4100!.round();
              return PGAlternative(
                dsldId: p.dsldId,
                name: p.productName,
                brand: p.brandName ?? '',
                score: score,
                qualityTier: p.qualityTier,
                scoreConfidence: p.v4Confidence,
                imageWidget: ProductImage(
                  dsldId: p.dsldId,
                  upc: p.upcSku,
                  dsldImagePath: p.imageThumbnailUrl ?? p.imageUrl,
                  productName: p.productName,
                  brandName: p.brandName ?? '',
                  formFactor: p.formFactor,
                  score: score.toDouble(),
                  size: 48,
                  compact: true,
                ),
                onTap: () => context.push('/product/${p.dsldId}'),
              );
            })
            .toList(growable: false);

        return PGBetterAlternatives(
          alternatives: mapped,
          // Title updated 2026-05-16 (Sean): ranker mixes
          // strict-quality with intent/family matching, so this
          // copy describes what we actually return.
          title: 'Similar higher-quality options',
          body: profileIncomplete
              ? 'Personalize for better matches — complete your profile '
                    'to rank options for your goals and health context.'
              : null,
        );
      },
    );
  }
}

class _BlockedAlternativesEmpty extends StatelessWidget {
  const _BlockedAlternativesEmpty();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'No comparable alternatives found. We could not find a similar, '
          'higher-quality option in this catalog.',
      child: Container(
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
              'No comparable alternatives found',
              style: V2Typography.titleSm(color: context.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space4),
            Text(
              'We couldn\'t find a similar, higher-quality option in this '
              'catalog.',
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
          ],
        ),
      ),
    );
  }
}
