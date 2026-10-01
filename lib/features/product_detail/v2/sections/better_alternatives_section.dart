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
  bool assessmentIncomplete = false,
  required double? score100,
  required bool profileIncomplete,
  String? qualityTier,
}) {
  if (isBlocked) return true;
  // An unfinished assessment has no completed verdict to improve on, so
  // "better alternatives" would be comparing against a number that is still
  // missing a pillar's worth of unearned points.
  if (isNotScored || assessmentIncomplete || score100 == null) return false;
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

/// Ranked alternatives for (current product, sorted goal ids joined by ",",
/// limit). Fetches the current product, builds a wider candidate pool
/// (on-market + strictly higher score + intent/family channels), then hands
/// it to `BetterAlternativesRanker` for the final relevance and tiebreaker
/// pass. Cached per key: a rebuild reuses the result instead of re-querying
/// the catalog and flashing the loading skeleton.
final betterAlternativesProvider = FutureProvider.autoDispose
    .family<List<ProductsCoreData>, (String, String, int)>((ref, key) async {
      final (currentDsldId, goalsKey, limit) = key;
      final coreDb = ref.watch(coreDatabaseProvider);
      final current = await coreDb.findById(currentDsldId);
      if (current == null) return const [];
      final pool = await coreDb.fetchBetterAlternativesPool(current);
      if (pool.isEmpty) return const [];
      return rankAlternatives(
        current: current,
        candidates: pool,
        userGoals: goalsKey.isEmpty ? null : goalsKey.split(',').toSet(),
        limit: limit,
      );
    });

/// The ranked alternatives for [dsldId], keyed exactly as the section keys
/// them, so the section and the page's sticky button read one cached result.
AsyncValue<List<ProductsCoreData>> watchBetterAlternatives(
  WidgetRef ref,
  String dsldId, {
  int limit = 3,
}) {
  // Personalize tiebreakers when the profile has goals (sentinel-stripped).
  final goals = ref.watch(profileProvider).goalsForEvaluator.toList()..sort();
  return ref.watch(
    betterAlternativesProvider((dsldId, goals.join(','), limit)),
  );
}

/// Quality-only alternatives section. Profile goals can break ties, but this
/// surface never claims candidate-level safety or personal fit.
class BetterAlternativesSection extends ConsumerWidget {
  final String currentDsldId;
  final bool isBlocked;
  final bool isNotScored;

  /// True when a number exists but the assessment behind it is unfinished.
  final bool assessmentIncomplete;
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
    this.assessmentIncomplete = false,
    required this.score100,
    required this.profileIncomplete,
    this.qualityTier,
    this.maxAlternatives = 3,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!shouldShowBetterAlternatives(
      isBlocked: isBlocked,
      isNotScored: isNotScored,
      assessmentIncomplete: assessmentIncomplete,
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

    final alternativesAsync = watchBetterAlternatives(
      ref,
      currentDsldId,
      limit: maxAlternatives,
    );

    return alternativesAsync.when(
      // Loading skeleton — keeps the sticky-CTA scroll anchor
      // landing on a real surface, not an empty slot mid-fetch.
      loading: () => const PGBetterAlternativesSkeleton(),
      // No alternatives: no section. The sticky button hides too, so the
      // page never offers options it cannot show.
      error: (_, _) => const SizedBox.shrink(),
      data: (alternatives) {
        if (alternatives.isEmpty) return const SizedBox.shrink();
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
                scoreConfidence: p.qualityScoreConfidence,
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
