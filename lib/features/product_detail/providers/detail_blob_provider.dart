// Detail blob provider — extracted from ProductDetailScreen so the screen
// can stay focused on layout and composition.
//
// Flow:
//   1. Consult the UserDatabase cache for the dsldId (24h TTL).
//   2. On cache miss/stale, look up the product in CoreDatabase to obtain
//      its SHA-256 hash.
//   3. Fetch the blob from Supabase Storage via [DetailBlobService].
//   4. Persist the fetched blob back to UserDatabase for next time.
//
// Returns `null` when the product has no SHA-256 (e.g. not-scored products)
// or when the remote fetch yields nothing. Exceptions (corrupt cache JSON,
// DB write errors) propagate as [AsyncError] so the UI can render a retry
// banner via `ref.invalidate(detailBlobProvider(dsldId))`.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';

/// 24-hour cache TTL for detail blobs. Kept in sync with the previous
/// inline value in ProductDetailScreen.
const Duration kDetailBlobCacheTtl = Duration(hours: 24);

/// Service provider — overridable in tests so the widget tree can fake
/// network fetches without touching Supabase.
final detailBlobServiceProvider = Provider<DetailBlobService>((ref) {
  return DetailBlobService();
});

/// Async detail-blob fetcher keyed by dsldId.
///
/// Autodisposes so navigating away from a product detail screen frees the
/// cached AsyncValue and triggers a fresh cache check on the next visit.
final detailBlobProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>?, String>((ref, dsldId) async {
      final coreDb = ref.watch(coreDatabaseProvider);
      final userDb = ref.watch(userDatabaseProvider);
      final service = ref.watch(detailBlobServiceProvider);

      // --- 1. Local cache (fast path) ---
      final cached = await userDb.getCachedDetail(dsldId);
      if (cached != null) {
        final age = DateTime.now().difference(cached.cachedAt);
        if (age < kDetailBlobCacheTtl) {
          // The cache row was written by us in jsonEncode form, but defend
          // against a corrupt entry by checking the decoded shape — a non-map
          // value would crash the entire detail screen if we cast blindly.
          try {
            final decoded = jsonDecode(cached.blobJson);
            if (decoded is Map<String, dynamic>) return decoded;
            if (decoded is Map) return Map<String, dynamic>.from(decoded);
          } on FormatException {
            // Fall through to network fetch below.
          }
        }
      }

      // --- 2. Resolve SHA-256 from the product row ---
      final product = await coreDb.findById(dsldId);
      final sha256 = product?.detailBlobSha256;
      if (sha256 == null || sha256.isEmpty) return null;

      // --- 3. Network fetch by content hash ---
      final blob = await service.fetchDetailBlobByHash(sha256);

      // --- 4. Persist to cache (best effort — failure here is rare and
      //      should surface as an error so the UI can retry).
      if (blob != null) {
        await userDb.cacheDetail(dsldId, jsonEncode(blob), null);
      }
      return blob;
    });
