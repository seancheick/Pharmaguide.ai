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
// profile edits → the `profileProvider` rebuild propagates because we use
// `ref.watch`.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/fit_score/e1_dosage_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2a_goal_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2b_age_calculator.dart';
import 'package:pharmaguide/services/fit_score/e2c_medical_calculator.dart';
import 'package:pharmaguide/services/fit_score/fit_score_service.dart';

/// Reference data repository — singleton that lazy-caches JSON asset loads.
final _refDataRepositoryProvider = Provider<ReferenceDataRepository>((ref) {
  return ReferenceDataRepository();
});

/// FutureProvider exposing a fully-constructed [FitScoreService].
///
/// The 3 data-backed calculators (E1 dosage, E2a goals, E2b age) need
/// reference JSON from `assets/reference_data/`, which requires an async
/// load. The repository caches after first load so subsequent reads are
/// synchronous.
final fitScoreServiceProvider = FutureProvider<FitScoreService>((ref) async {
  final repo = ref.watch(_refDataRepositoryProvider);
  final rdaData = await repo.loadRdaOptimalUls();
  final goalData = await repo.loadGoalMappings();

  return FitScoreService(
    e1: E1DosageCalculator(rdaData),
    e2a: E2aGoalCalculator(goalData),
    e2b: E2bAgeCalculator(rdaData),
    e2c: E2cMedicalCalculator(),
  );
});

/// Shared detail-blob fetcher (matches the pattern used by the M1 nutrient
/// panel provider — cache-first with 24h TTL, graceful offline behavior).
final _fitScoreBlobServiceProvider = Provider<DetailBlobService>((ref) {
  return DetailBlobService();
});

final _fitScoreBlobByDsldIdProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>?, String>((ref, dsldId) async {
      final userDb = ref.watch(userDatabaseProvider);
      final service = ref.watch(_fitScoreBlobServiceProvider);

      const cacheTtl = Duration(hours: 24);
      final cached = await userDb.getCachedDetail(dsldId);
      if (cached != null) {
        final age = DateTime.now().difference(cached.cachedAt);
        if (age < cacheTtl) {
          try {
            final decoded = jsonDecode(cached.blobJson);
            if (decoded is Map<String, dynamic>) return decoded;
            if (decoded is Map) return Map<String, dynamic>.from(decoded);
            // Decoded to an unexpected shape (List/scalar). Treat as corrupt
            // cache and fall through to the network fetch below.
          } on FormatException {
            // Malformed JSON — fall through to network.
          }
        }
      }

      // Look up the SHA-256 hash from the core DB to fetch the blob.
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

      // Watch the profile so every profile edit (add a condition, set age, etc)
      // automatically invalidates this provider and recomputes. FitScore must
      // never be persisted — it's a fresh computation every time.
      final profile = ref.watch(profileProvider);

      // Product row (for score_quality_80 + primary_category → cluster)
      ProductsCoreData? product;
      try {
        product = await coreDb.findById(dsldId);
      } on Exception {
        return null;
      }
      if (product == null) return null;

      // Detail blob (for ingredients nutrients + interaction_summary)
      Map<String, dynamic>? blob;
      try {
        blob = await ref.watch(_fitScoreBlobByDsldIdProvider(dsldId).future);
      } on Exception {
        return null;
      }
      if (blob == null) return null;

      final nutrients = _extractNutrients(blob);
      final interactionSummary = _extractInteractionSummary(blob);
      final productClusters = extractFitProductClusters(blob);
      final productGoalMatches = _extractGoalMatches(product);

      return service.calculate(
        nutrients: nutrients,
        productClusters: productClusters,
        productGoalMatches: productGoalMatches,
        productGoalMatchConfidence: product.goalMatchConfidence,
        interactionSummary: interactionSummary,
        ageBracket: profile.ageBracket,
        sex: profile.sex,
        userGoals: profile.goals,
        userConditions: profile.conditions,
        userDrugClasses: profile.drugClasses,
        mappedCoverage: product.mappedCoverage ?? 0.0,
      );
    });

// ---------------------------------------------------------------------------
// Blob extractors — tolerant of the multiple shapes the pipeline has emitted.
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _extractNutrients(Map<String, dynamic> blob) {
  // Preferred: top-level ingredients list
  final direct = blob['ingredients'];
  if (direct is List) {
    return direct.whereType<Map<String, dynamic>>().toList(growable: false);
  }
  // Fallback: nested under ingredient_quality_data
  final iqd = blob['ingredient_quality_data'];
  if (iqd is Map<String, dynamic>) {
    final nested = iqd['ingredients'] ?? iqd['ingredients_scorable'];
    if (nested is List) {
      return nested.whereType<Map<String, dynamic>>().toList(growable: false);
    }
  }
  return const [];
}

Map<String, dynamic> _extractInteractionSummary(Map<String, dynamic> blob) {
  final raw = blob['interaction_summary'];
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  return const {};
}

List<String> extractFitProductClusters(Map<String, dynamic> blob) {
  // Prefer explicit clusters in the blob if present
  final raw = blob['product_clusters'];
  if (raw is List) {
    return raw.map((e) => e.toString()).toList(growable: false);
  }

  // Current final-DB blobs expose formulation cluster matches under
  // synergy_detail.clusters[*].cluster_id. This keeps the goal fallback
  // alive when products_core.goal_matches is empty or malformed.
  final synergyDetail = blob['synergy_detail'];
  if (synergyDetail is Map) {
    final clusters = synergyDetail['clusters'];
    if (clusters is List) {
      return clusters
          .whereType<Map<Object?, Object?>>()
          .map((cluster) => cluster['cluster_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }
  }

  final formulationData = blob['formulation_data'];
  if (formulationData is Map) {
    final clusters = formulationData['synergy_clusters'];
    if (clusters is List) {
      return clusters
          .whereType<Map<Object?, Object?>>()
          .map((cluster) => cluster['cluster_id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }
  }

  return const [];
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
