// Shared detail-blob provider.
//
// Flow:
//   1. Look up the product in CoreDatabase to obtain its CURRENT
//      SHA-256 hash (`detail_blob_sha256`).
//   2. Consult the UserDatabase cache for the dsldId — served only when
//      its recorded sha matches the product's hash. Age never makes a row a
//      miss: a verdict must not change because time passed or the phone was
//      offline.
//   3. On cache miss/stale/sha-mismatch, fetch the blob from Supabase
//      Storage via [DetailBlobService] (which checksum-verifies the
//      bytes against the hash before parsing).
//   4. Persist the fetched blob back to UserDatabase WITH its verified
//      sha, so step 2 can re-validate it on every later read.

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/services/connectivity_service.dart';

/// PURE serve decision for a cached detail-blob row.
///
/// A cached row is served only when its recorded [cachedSha256] equals the
/// product row's CURRENT [productSha256] (null-safe equality). Blobs are
/// content-addressed, so a matching hash means the bytes are exactly the ones
/// the installed catalog declares, however long ago they were fetched.
///
/// A catalog update that re-points the product at a new blob therefore
/// reads as a MISS instead of serving the previous snapshot's JSON; so does
/// a legacy cache row (sha persisted as null) for a product that declares a
/// blob hash.
@visibleForTesting
bool cachedDetailIsServable({
  required String? cachedSha256,
  required String? productSha256,
}) {
  return cachedSha256 == productSha256;
}

/// App-wide detail-blob service provider. Overridable in tests.
final detailBlobServiceProvider = Provider<DetailBlobService>((ref) {
  // Inject connectivity so a known-offline device skips the network entirely
  // instead of burning the retry budget and emitting error spans.
  // `ref.read` inside the closure keeps ConnectivityService lazy: it is only
  // constructed when a fetch actually runs, so provider-graph tests that never
  // fetch do not need a platform binding.
  return DetailBlobService(
    isOffline: () =>
        ref.read(connectivityServiceProvider).current ==
        ConnectionStatus.offline,
  );
});

/// Async detail-blob fetcher keyed by dsldId.
///
/// Autodisposes so consumers do not keep large detail blobs alive after
/// leaving the relevant product/stack surface.
final detailBlobProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>?, String>(
      (ref, dsldId) async {
        final coreDb = ref.watch(coreDatabaseProvider);
        final userDb = ref.watch(userDatabaseProvider);
        final service = ref.watch(detailBlobServiceProvider);

        // The product row is read FIRST so the cache check can compare the
        // cached sha against the product's CURRENT detail_blob_sha256 — a
        // cached blob from a previous catalog snapshot must be a miss, not
        // a stale hit feeding outdated ingredient/warning JSON.
        final product = await coreDb.findById(dsldId);
        final expectedSha = product?.detailBlobSha256;

        final cached = await userDb.getCachedDetail(dsldId);
        if (cached != null &&
            cachedDetailIsServable(
              cachedSha256: cached.sha256,
              productSha256: expectedSha,
            )) {
          try {
            final decoded = jsonDecode(cached.blobJson);
            if (decoded is Map<String, dynamic>) return decoded;
            if (decoded is Map) return Map<String, dynamic>.from(decoded);
          } on FormatException {
            // Fall through to network fetch below.
          }
        }

        if (expectedSha == null || expectedSha.isEmpty) return null;

        final blob = await service.fetchDetailBlobByHash(expectedSha);
        if (blob == null) {
          throw const DetailBlobUnavailableException(
            'detail service returned no payload for a declared blob',
          );
        }
        // Persist the sha alongside the blob: the fetch path verified
        // sha256(bytes) == expectedSha, so the cached row stays
        // re-checkable against products_core on every later read.
        await userDb.cacheDetail(dsldId, jsonEncode(blob), expectedSha);
        return blob;
      },
      // An unavailable clinical blob must settle as an error immediately so
      // the surface can render its explicit unavailable state. Riverpod's
      // default automatic retry otherwise keeps the provider in loading for
      // multiple backoff cycles and can look like an empty/all-clear result.
      // User-initiated refresh/invalidation remains the retry mechanism.
      retry: (_, _) => null,
    );
