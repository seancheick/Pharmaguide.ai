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
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart'
    as ref_data;
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';
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
/// Empty stack returns an empty result (not an error). A stack item whose
/// product row or detail blob cannot be loaded is skipped so one broken
/// product can't break the whole panel — but the skip is REPORTED via
/// [StackNutrientStatuses.incomplete] rather than silently absorbed. A
/// partial sum under-reports intake, so a UL comparison drawn from it can
/// read "within limit" when the true total is not; the panel hedges instead
/// of presenting the number as the user's complete intake.
final stackNutrientStatusesProvider = FutureProvider<StackNutrientStatuses>((
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
    return const StackNutrientStatuses.empty();
  }

  // Load product + detail blob for every stack entry.
  final items = <StackItemNutrients>[];
  var incomplete = false;
  for (final entry in stackEntries) {
    // Medications carry no nutrient rows by design — not a data gap.
    if (entry.type == 'medication') continue;

    final dsldId = entry.dsldId;
    if (dsldId == null || dsldId.isEmpty) {
      incomplete = true;
      continue;
    }

    ProductsCoreData? product;
    try {
      product = await coreDb.findById(dsldId);
    } on Object {
      incomplete = true;
      continue;
    }
    if (product == null) {
      incomplete = true;
      continue;
    }

    Map<String, dynamic>? blob;
    try {
      blob = await ref.watch(detailBlobProvider(dsldId).future);
    } on Object {
      incomplete = true;
      continue;
    }
    if (blob == null) {
      incomplete = true;
      continue;
    }

    List<Map<String, dynamic>> ingredients;
    try {
      ingredients = ProductHealthFacts.fromDetailBlob(blob).nutrients;
    } on Object {
      incomplete = true;
      continue;
    }
    // A product with no nutrient rows contributes nothing to a nutrient
    // total legitimately (botanicals, probiotics) — not a load failure.
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
    return StackNutrientStatuses(
      statuses: const <NutrientStatus>[],
      incomplete: incomplete,
    );
  }

  const aggregator = StackNutrientAggregator();
  final totals = aggregator.aggregate(items);

  final rdaData = await refRepo.loadRdaOptimalUls();
  final checker = StackUlChecker(rdaData: rdaData);
  final statuses = checker.check(
    totals,
    ageBracket: demographics.ageBracket,
    sex: demographics.sex,
    pipelineVerdicts: aggregator.extractPipelineUlVerdicts(items),
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

  return StackNutrientStatuses(statuses: sorted, incomplete: incomplete);
});

final stackDoseThresholdAlertsProvider =
    FutureProvider<List<StackDoseThresholdAlert>>((ref) async {
      final userDb = ref.watch(userDatabaseProvider);
      final coreDb = ref.watch(coreDatabaseProvider);
      final profile = await ref.watch(loadedProfileProvider.future);

      final stackEntries = await userDb.getActiveStack();
      if (stackEntries.isEmpty) {
        return const <StackDoseThresholdAlert>[];
      }
      final activeDrugClasses = profile.drugClasses.toSet();
      final bridgeClassIds = <String>[];
      for (final entry in stackEntries) {
        if (entry.type != 'medication') continue;
        final raw = entry.drugClassesCol;
        if (raw == null || raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            bridgeClassIds.addAll(
              decoded
                  .map((value) => value.toString().trim())
                  .where((value) => value.isNotEmpty),
            );
          }
        } on FormatException {
          // Malformed local metadata contributes no class. The existing
          // medication safety surface remains responsible for its diagnostics.
        }
      }
      activeDrugClasses.addAll(
        MedicationClassBridge.profileGateIdsForClasses(bridgeClassIds),
      );
      if (profile.conditions.isEmpty && activeDrugClasses.isEmpty) {
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

        final facts = ProductHealthFacts.fromDetailBlob(blob);
        thresholdRules.addAll(
          stackDoseThresholdRulesFromWarnings(
            facts.warnings,
            stackEntryId: entry.id,
            productName: entry.name,
          ),
        );

        final ingredients = facts.doseRowsForThresholds;
        if (ingredients.isEmpty) continue;
        items.add(
          StackItemNutrients(
            stackEntryId: entry.id,
            productName: entry.name,
            ingredients: ingredients,
          ),
        );
      }

      if (thresholdRules.isEmpty) return const <StackDoseThresholdAlert>[];

      const summer = StackDoseSummer();
      final hasNormalizedRules = thresholdRules.any(
        (rule) =>
            rule.normalizedDailyAmount != null &&
            rule.normalizedDailyUnit?.isNotEmpty == true,
      );
      if (hasNormalizedRules) {
        return summer.thresholdAlertsFromNormalizedRules(
          userConditions: profile.conditions,
          userDrugClasses: activeDrugClasses,
          thresholdRules: thresholdRules,
        );
      }

      // Compatibility for a cached pre-contract catalog. Fresh catalogs use
      // only the normalized path above; this branch can be removed after the
      // catalog cache rollover window.
      if (items.isEmpty) return const <StackDoseThresholdAlert>[];
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
