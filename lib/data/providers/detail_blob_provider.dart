// Shared detail-blob provider.
//
// Flow:
//   1. Consult the UserDatabase cache for the dsldId (24h TTL).
//   2. On cache miss/stale, look up the product in CoreDatabase to obtain
//      its SHA-256 hash.
//   3. Fetch the blob from Supabase Storage via [DetailBlobService].
//   4. Persist the fetched blob back to UserDatabase for next time.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';

/// 24-hour cache TTL for detail blobs.
const Duration kDetailBlobCacheTtl = Duration(hours: 24);

/// App-wide detail-blob service provider. Overridable in tests.
final detailBlobServiceProvider = Provider<DetailBlobService>((ref) {
  return DetailBlobService();
});

/// Async detail-blob fetcher keyed by dsldId.
///
/// Autodisposes so consumers do not keep large detail blobs alive after
/// leaving the relevant product/stack surface.
final detailBlobProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>?, String>((ref, dsldId) async {
      final coreDb = ref.watch(coreDatabaseProvider);
      final userDb = ref.watch(userDatabaseProvider);
      final service = ref.watch(detailBlobServiceProvider);

      final cached = await userDb.getCachedDetail(dsldId);
      if (cached != null) {
        final age = DateTime.now().difference(cached.cachedAt);
        if (age < kDetailBlobCacheTtl) {
          try {
            final decoded = jsonDecode(cached.blobJson);
            if (decoded is Map<String, dynamic>) return decoded;
            if (decoded is Map) return Map<String, dynamic>.from(decoded);
          } on FormatException {
            // Fall through to network fetch below.
          }
        }
      }

      final product = await coreDb.findById(dsldId);
      final sha256 = product?.detailBlobSha256;
      if (sha256 == null || sha256.isEmpty) return null;

      final blob = await service.fetchDetailBlobByHash(sha256);
      if (blob != null) {
        await userDb.cacheDetail(dsldId, jsonEncode(blob), null);
      }
      return blob;
    });
