// Riverpod providers for the stack nutrient accumulation feature (M1).
//
// The service layer ([StackNutrientAggregator] and [StackUlChecker]) is
// pure and synchronous. This file is the async glue: it loads the
// user's stack, fetches each product's detail blob (from cache when
// possible, Supabase when not), feeds the aggregator, applies the UL
// checker with the user's profile, and surfaces the result as an
// [AsyncValue] for the widget layer.
//
// Caching strategy: detail blobs are stored in `user_data.db` with a
// 24-hour TTL, matching the product detail screen's behavior. If the
// user is offline with a warm cache, this provider works entirely
// offline. If the cache is stale or empty, it falls back to Supabase
// Storage. Errors are surfaced as [AsyncError] so the widget can show
// a retry affordance.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_ul_checker.dart';

/// Singleton detail-blob service. Thin client around Supabase Storage.
final detailBlobServiceProvider = Provider<DetailBlobService>((ref) {
  return DetailBlobService();
});

/// Singleton reference-data repository that caches JSON asset loads.
/// Kept as a Provider so the cache persists for the app's lifetime —
/// rda_optimal_uls.json is small and the cache hit rate is ~100%.
final referenceDataRepositoryProvider = Provider<ReferenceDataRepository>((
  ref,
) {
  return ReferenceDataRepository();
});

/// Async map: `dsldId` → parsed detail blob. Used internally by the
/// nutrient-status provider. Exposed separately so future features can
/// reuse the same cache-first lookup.
final _detailBlobByDsldIdProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, dsldId) async {
      final userDb = ref.watch(userDatabaseProvider);
      final service = ref.watch(detailBlobServiceProvider);

      // Cache-first: check local store, honour 24-hour TTL.
      const cacheTtl = Duration(hours: 24);
      final cached = await userDb.getCachedDetail(dsldId);
      if (cached != null) {
        final age = DateTime.now().difference(cached.cachedAt);
        if (age < cacheTtl) {
          try {
            final decoded = jsonDecode(cached.blobJson);
            if (decoded is Map<String, dynamic>) return decoded;
            if (decoded is Map) return Map<String, dynamic>.from(decoded);
            // Decoded to an unexpected shape — fall through to network.
          } on FormatException {
            // Corrupt cache entry — fall through to network fetch.
          }
        }
      }

      // Cache miss or stale — fetch from Supabase by SHA-256 hash.
      final coreDb = ref.watch(coreDatabaseProvider);
      final product = await coreDb.findById(dsldId);
      final sha256 = product?.detailBlobSha256;
      if (sha256 == null || sha256.isEmpty) return null;

      final blob = await service.fetchDetailBlobByHash(sha256);
      if (blob != null) {
        await userDb.cacheDetail(dsldId, jsonEncode(blob), null);
      }
      return blob;
    });

/// The primary M1 provider. Returns a list of [NutrientStatus]
/// classifications for every nutrient present in the user's stack.
///
/// Output is sorted most-severe-first: [NutrientTier.exceedsUl] rows
/// come first, then [NutrientTier.approachingUl], then by RDA% descending
/// within the remaining tiers.
///
/// Empty stack returns an empty list (not an error). Products whose
/// detail blobs cannot be fetched are silently skipped — M1 is a
/// best-effort safety surface, not a hard gate. If every blob fails to
/// load the result is still an empty list with no thrown error.
final stackNutrientStatusesProvider = FutureProvider<List<NutrientStatus>>((
  ref,
) async {
  final userDb = ref.watch(userDatabaseProvider);
  final coreDb = ref.watch(coreDatabaseProvider);
  final refRepo = ref.watch(referenceDataRepositoryProvider);

  // Reach into the profile state for age/sex — we don't ref.watch the
  // notifier because the nutrient math shouldn't rebuild on every
  // goal/allergen edit.
  final profile = ref.read(profileProvider);

  final stackEntries = await userDb.getActiveStack();
  if (stackEntries.isEmpty) {
    return const <NutrientStatus>[];
  }

  // Load product + detail blob for every stack entry. Any item
  // missing either is silently skipped so one broken product can't
  // break the whole panel.
  final items = <StackItemNutrients>[];
  for (final entry in stackEntries) {
    final dsldId = entry.dsldId;
    if (dsldId == null || dsldId.isEmpty) continue;

    ProductsCoreData? product;
    try {
      product = await coreDb.findById(dsldId);
    } on Exception {
      continue;
    }
    if (product == null) continue;

    Map<String, dynamic>? blob;
    try {
      blob = await ref.watch(_detailBlobByDsldIdProvider(dsldId).future);
    } on Exception {
      continue;
    }
    if (blob == null) continue;

    final ingredients = _readIngredientsList(blob);
    if (ingredients.isEmpty) continue;

    items.add(
      StackItemNutrients(
        stackEntryId: entry.id,
        productName: entry.name,
        ingredients: ingredients,
      ),
    );
  }

  if (items.isEmpty) {
    return const <NutrientStatus>[];
  }

  const aggregator = StackNutrientAggregator();
  final totals = aggregator.aggregate(items);

  final rdaData = await refRepo.loadRdaOptimalUls();
  final checker = StackUlChecker(rdaData: rdaData);
  final statuses = checker.check(
    totals,
    ageBracket: profile.ageBracket,
    sex: profile.sex,
  );

  // Sort most-severe-first. Within a tier, RDA% descending so the
  // most over-supplemented items in each band surface first.
  final sorted = [...statuses];
  sorted.sort((a, b) {
    final tierDiff = b.tier.index.compareTo(a.tier.index);
    if (tierDiff != 0) return tierDiff;
    final aPct = a.pctOfRda ?? 0.0;
    final bPct = b.pctOfRda ?? 0.0;
    return bPct.compareTo(aPct);
  });

  return sorted;
});

/// Extract the ingredients list from a detail blob, tolerating both
/// `ingredients` and `ingredient_quality_data.ingredients` shapes the
/// pipeline has emitted over time. Returns an empty list if neither
/// is present or parseable.
List<Map<String, dynamic>> _readIngredientsList(Map<String, dynamic> blob) {
  final direct = blob['ingredients'];
  if (direct is List) {
    return direct.whereType<Map<String, dynamic>>().toList(growable: false);
  }
  final iqd = blob['ingredient_quality_data'];
  if (iqd is Map<String, dynamic>) {
    final nested = iqd['ingredients'] ?? iqd['ingredients_scorable'];
    if (nested is List) {
      return nested.whereType<Map<String, dynamic>>().toList(growable: false);
    }
  }
  return const <Map<String, dynamic>>[];
}
