// Riverpod providers for the FitScore feature (Sprint 4 UI integration).
//
// The FitScoreService itself is already built and covered by 9 unit tests.
// This file is the async glue that:
//
//   1. Reads the user profile (ageBracket/sex/goals/conditions/drugClasses)
//   2. Loads a product's detail blob (with 24h cache via _detailBlobByDsldId)
//   3. Extracts nutrients + clusters + interaction_summary from the blob
//   4. Runs FitScoreService.calculate() with both sides
//   5. Surfaces the `FitScoreResult` as an `AsyncValue` for widgets
//
// **Critical invariant:** FitScore is NEVER persisted. Every read is a fresh
// computation. The family-keyed provider auto-invalidates when either side
// of the computation changes: different product → different family key;
// profile edits → `loadedProfileProvider` rebuilds after persistence has
// resolved because we use `ref.watch`.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart';
import 'package:pharmaguide/features/product_detail/providers/profile_warning_rule_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2c_medical_calculator.dart';
import 'package:pharmaguide/services/fit_score/fit_score_service.dart';
import 'package:pharmaguide/services/health/product_health_facts.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/warnings/profile_gate_summary_filter.dart';

/// FutureProvider exposing a fully-constructed [FitScoreService].
///
/// The 3 data-backed calculators (E1 dosage, E2a goals, E2b age) need
/// reference JSON from `assets/reference_data/`, which requires an async
/// load. The repository caches after first load so subsequent reads are
/// synchronous.
final fitScoreServiceProvider = FutureProvider<FitScoreService>((ref) async {
  final repo = ref.watch(referenceDataRepositoryProvider);
  final rdaData = await repo.loadRdaOptimalUls();
  final goalData = await repo.loadGoalMappings();

  return FitScoreService(
    e1: E1DosageCalculator(rdaData),
    e2a: E2aGoalCalculator(goalData),
    e2b: E2bAgeCalculator(rdaData),
    e2c: E2cMedicalCalculator(),
  );
});

/// Primary FitScore provider, keyed by `dsldId`.
///
/// Returns `null` when:
///   - The product isn't in the local core DB
///   - The detail blob can't be fetched (offline first run)
///   - The blob has no scorable ingredients
///
/// Returns a [FitScoreResult] with `missingFields` populated when the user's
/// profile is incomplete — the UI uses that to show a "complete your profile"
/// prompt instead of a misleading low score.
final fitScoreForProductProvider = FutureProvider.family
    .autoDispose<FitScoreResult?, String>((ref, dsldId) async {
      final service = await ref.watch(fitScoreServiceProvider.future);
      final coreDb = ref.watch(coreDatabaseProvider);

      // Wait for the persisted profile before computing. A brief default
      // profile during cold start would otherwise produce a misleading
      // generic FitScore until the DB load finishes. FitScore must never be
      // persisted — it's a fresh computation every time.
      final profile = await ref.watch(loadedProfileProvider.future);
      final userProfileFlags = await ref.watch(
        evaluatorProfileFlagsProvider.future,
      );
      // Include the classes of meds the user added to their stack (same
      // resolved source stack safety uses) so the medical (E2c) penalty
      // reflects added medications, not just the profile picker chips.
      final stackMedicationClassIds = await ref.watch(
        currentStackMedicationClassIdsProvider.future,
      );

      // Product row (for quality_score_v4_100 + primary_category → cluster)
      ProductsCoreData? product;
      try {
        product = await coreDb.findById(dsldId);
      } on Object catch (error, stackTrace) {
        CrashReportingService().recordError(
          error,
          stackTrace,
          fatal: false,
          hint: 'fit_score:product_fetch_failed',
        );
        rethrow;
      }
      if (product == null) return null;

      // Detail blob (for ingredients nutrients + interaction_summary)
      Map<String, dynamic>? blob;
      try {
        blob = await ref.watch(detailBlobProvider(dsldId).future);
      } on Object catch (error, stackTrace) {
        CrashReportingService().recordError(
          error,
          stackTrace,
          fatal: false,
          hint: 'fit_score:detail_fetch_failed',
        );
        rethrow;
      }
      if (blob == null) return null;

      final resolvedRuleWarnings = await ref.watch(
        profileWarningRuleWarningsProvider(dsldId).future,
      );
      final healthFacts = ProductHealthFacts.fromDetailBlob(
        blob,
        resolvedRuleWarnings: resolvedRuleWarnings,
      );
      final nutrients = healthFacts.nutrients;
      final interactionSummary = healthFacts.interactionSummary;
      final productClusters = healthFacts.productClusters;
      final productGoalMatches = _extractGoalMatches(product);
      // v6.0 — parse warnings carrying profile_gate so Fit Score can
      // suppress condition/drug-class penalties whose underlying gates
      // don't fire (e.g., topical-only aloe under pregnancy).
      final warnings = healthFacts.warnings;

      return service.calculate(
        nutrients: nutrients,
        productClusters: productClusters,
        productGoalMatches: productGoalMatches,
        productGoalMatchConfidence: product.goalMatchConfidence,
        interactionSummary: interactionSummary,
        ageBracket: profile.ageBracket,
        sex: _rdaGroupForProfile(profile.sex, profile.conditions),
        userGoals: profile.goals,
        userConditions: profile.conditionsForEvaluator,
        userDrugClasses: <String>{
          ...profile.drugClassesForEvaluator,
          ...stackMedicationClassIds,
        }.toList(),
        mappedCoverage: product.mappedCoverage ?? 0.0,
        warnings: warnings,
        userProfileFlags: userProfileFlags,
        productForm: product.formFactor,
        productContextForWarning: (warning) => resolveProfileGateProductContext(
          detailBlob: blob,
          warning: warning,
          productForm: product?.formFactor,
        ),
      );
    });

// ---------------------------------------------------------------------------
// Blob extractors — tolerant of the multiple shapes the pipeline has emitted.
// ---------------------------------------------------------------------------

String? _rdaGroupForProfile(String? sex, List<String> conditions) {
  final normalizedConditions = conditions.map((c) => c.toLowerCase()).toSet();
  if (normalizedConditions.contains('pregnancy')) return 'Pregnancy';
  if (normalizedConditions.contains('lactation')) return 'Lactation';
  return sex;
}

List<String> extractFitProductClusters(Map<String, dynamic> blob) {
  return ProductHealthFacts.fromDetailBlob(blob).productClusters;
}

List<String> _extractGoalMatches(ProductsCoreData product) {
  final raw = product.goalMatches;
  if (raw == null || raw.isEmpty) return const [];

  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.map((e) => e.toString()).toList(growable: false);
    }
  } on FormatException {
    // Keep fit resilient to malformed rows and fall back to cluster matching.
  }

  return const [];
}
