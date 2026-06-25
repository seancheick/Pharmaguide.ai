// Phase 11.7e — BetterAlternatives section adapter (S16).
//
// Better Alternatives v2 section.
//
// Gate rules (verbatim port via `shouldShowBetterAlternatives`):
//   • product is blocked → ALWAYS render
//   • product unscored → hide
//   • score < 60 → render
//   • Profile Relevance is review / notRecommended → render
//
// Data flow:
//   1. Consume the centralized ProfileRelevanceStatus from product detail
//   2. Check gate → SizedBox.shrink if not applicable
//   3. FutureBuilder loads CoreDatabase.findAlternatives by category
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
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/review_before_use_section.dart';
import 'package:pharmaguide/services/recommendations/better_alternatives_ranker.dart';

const double _lowQualityThreshold = 60.0;

/// Pure helper — should the Better Alternatives section render for this
/// product + user state?
bool shouldShowBetterAlternatives({
  required bool isBlocked,
  required bool isNotScored,
  required double? score100,
  required ProfileRelevanceStatus? profileRelevanceStatus,
  required bool profileIncomplete,
}) {
  if (isBlocked) return true;
  if (isNotScored || score100 == null) return false;
  if (score100 < _lowQualityThreshold) return true;
  if (profileIncomplete) return false;
  if (profileRelevanceStatus == ProfileRelevanceStatus.review ||
      profileRelevanceStatus == ProfileRelevanceStatus.notRecommended) {
    return true;
  }
  return false;
}

/// BetterAlternatives section. It consumes the already-resolved Profile
/// Relevance status so this section does not recompute personalization.
class BetterAlternativesSection extends ConsumerWidget {
  final String currentDsldId;
  final bool isBlocked;
  final bool isNotScored;
  final double? score100;
  final String? category;
  final ProfileRelevanceStatus? profileRelevanceStatus;
  final bool profileIncomplete;

  /// Max alternatives to display (matches PGBetterAlternatives convention).
  final int maxAlternatives;

  const BetterAlternativesSection({
    super.key,
    required this.currentDsldId,
    required this.isBlocked,
    required this.isNotScored,
    required this.score100,
    required this.category,
    required this.profileRelevanceStatus,
    required this.profileIncomplete,
    this.maxAlternatives = 3,
  });

  /// Fetches the current product, builds a wider candidate pool
  /// (on-market + strictly higher score + matching category OR
  /// supplement_type), then hands it to `BetterAlternativesRanker`
  /// for tier + tiebreaker sorting.
  Future<List<ProductsCoreData>> _loadRanked(CoreDatabase coreDb) async {
    final current = await coreDb.findById(currentDsldId);
    if (current == null) return const [];
    final pool = await coreDb.fetchBetterAlternativesPool(current);
    if (pool.isEmpty) return const [];
    return rankAlternatives(
      current: current,
      candidates: pool,
      limit: maxAlternatives,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!shouldShowBetterAlternatives(
      isBlocked: isBlocked,
      isNotScored: isNotScored,
      score100: score100,
      profileRelevanceStatus: profileRelevanceStatus,
      profileIncomplete: profileIncomplete,
    )) {
      return const SizedBox.shrink();
    }

    // Phase 11.7L.F follow-up (Sean 2026-05-16): no category gate
    // here. `fetchBetterAlternativesPool` handles category OR
    // supplement_type matching, and Vinpocetine-style blocked
    // products have empty category but a usable supplement_type.

    final coreDb = ref.watch(coreDatabaseProvider);

    return FutureBuilder<List<ProductsCoreData>>(
      future: _loadRanked(coreDb),
      builder: (context, snapshot) {
        // Loading skeleton — keeps the sticky-CTA scroll anchor
        // landing on a real surface, not an empty slot mid-fetch.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const PGBetterAlternativesSkeleton();
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final alternatives = snapshot.data!;
        final mapped = alternatives
            .map((p) {
              final score = p.qualityScoreV4100?.round() ?? 0;
              return PGAlternative(
                dsldId: p.dsldId,
                name: p.productName,
                brand: p.brandName ?? '',
                score: score,
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
        );
      },
    );
  }
}
