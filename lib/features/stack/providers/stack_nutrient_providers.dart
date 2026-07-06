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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart'
    as ref_data;
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/health/product_health_facts.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_ul_checker.dart';

/// Backwards-compatible export for stack modules that imported the shared
/// provider from this file before it moved to the data layer.
final referenceDataRepositoryProvider =
    ref_data.referenceDataRepositoryProvider;

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

  final profile = await ref.watch(loadedProfileProvider.future);
  final demographics = (
    ageBracket: profile.ageBracket,
    sex: _rdaGroupForProfile(profile.sex, profile.conditions),
  );

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
      blob = await ref.watch(detailBlobProvider(dsldId).future);
    } on Exception {
      continue;
    }
    if (blob == null) continue;

    final ingredients = ProductHealthFacts.fromDetailBlob(blob).nutrients;
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
    ageBracket: demographics.ageBracket,
    sex: demographics.sex,
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

final stackDoseThresholdAlertsProvider =
    FutureProvider<List<StackDoseThresholdAlert>>((ref) async {
      final userDb = ref.watch(userDatabaseProvider);
      final coreDb = ref.watch(coreDatabaseProvider);
      final profile = await ref.watch(loadedProfileProvider.future);

      final stackEntries = await userDb.getActiveStack();
      if (stackEntries.isEmpty || profile.conditions.isEmpty) {
        return const <StackDoseThresholdAlert>[];
      }

      final items = <StackItemNutrients>[];
      final thresholdRules = <StackDoseThresholdRule>[];
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
          blob = await ref.watch(detailBlobProvider(dsldId).future);
        } on Exception {
          continue;
        }
        if (blob == null) continue;
        thresholdRules.addAll(stackDoseThresholdRulesFromDetailBlob(blob));

        final doses = ProductHealthFacts.fromDetailBlob(blob).ingredientDoses;
        if (doses.isEmpty) continue;

        items.add(
          StackItemNutrients(
            stackEntryId: entry.id,
            productName: entry.name,
            ingredients: [
              for (final dose in doses.entries)
                {
                  'standard_name': dose.key,
                  'quantity': dose.value.value,
                  'unit': dose.value.unit,
                },
            ],
          ),
        );
      }

      if (items.isEmpty) return const <StackDoseThresholdAlert>[];

      const summer = StackDoseSummer();
      return summer.thresholdAlerts(
        totals: summer.sum(items),
        userConditions: profile.conditions,
        thresholdRules: thresholdRules,
      );
    });

String? _rdaGroupForProfile(String? sex, List<String> conditions) {
  final normalizedConditions = conditions.map((c) => c.toLowerCase()).toSet();
  if (normalizedConditions.contains('pregnancy')) return 'Pregnancy';
  if (normalizedConditions.contains('lactation')) return 'Lactation';
  // Only 'Male'/'Female' exist as reference-data groups. 'Other' /
  // 'Prefer not to say' normalize to null so the checker takes its
  // conservative flagged fallback instead of string-matching nothing
  // and silently landing on the first (Male) row.
  if (sex == 'Male' || sex == 'Female') return sex;
  return null;
}
