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
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/services/connectivity_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

/// PURE serve decision for a cached detail-blob row.
///
/// A cached row is served only when its recorded [cachedSha256] equals the
/// product row's CURRENT, non-empty [productSha256]. Blobs are
/// content-addressed, so a matching hash means the bytes are exactly the ones
/// the installed catalog declares, however long ago they were fetched.
///
/// A catalog update that re-points the product at a new blob therefore
/// reads as a MISS instead of serving the previous snapshot's JSON. A legacy
/// row with no hash, or a product that declares none, has nothing to verify
/// against and is never served.
@visibleForTesting
bool cachedDetailIsServable({
  required String? cachedSha256,
  required String? productSha256,
}) {
  if (productSha256 == null || productSha256.isEmpty) return false;
  return cachedSha256 == productSha256;
}

/// Fetches the active stack's blobs as a [candidate] catalog declares them, so
/// an update can't leave a stack waiting for a connection (ADR-012). Returns the
/// step that stores them, which the release store runs last: a fetch that fails
/// here throws, the phone stays on its release, and its cached blobs stay valid
/// for that release. A blob is never reused across releases by assumption, only
/// when its hash matches.
Future<Future<void> Function()> fetchStackDetailForRelease({
  required CoreDatabase candidate,
  required UserDatabase userDb,
  required DetailBlobService service,
}) async {
  final fetched = <String, ({String json, String sha256})>{};
  final stack = await userDb.getActiveStack();
  for (final id in {
    for (final item in stack)
      if (item.dsldId case final id? when id.isNotEmpty) id,
  }) {
    final expectedSha = (await candidate.findById(id))?.detailBlobSha256;
    if (expectedSha == null || expectedSha.isEmpty) continue;
    final cached = await userDb.getCachedDetail(id);
    if (cachedDetailIsServable(
      cachedSha256: cached?.sha256,
      productSha256: expectedSha,
    )) {
      continue;
    }
    final blob = await service.fetchDetailBlobByHash(expectedSha);
    if (blob == null) {
      throw const DetailBlobUnavailableException(
        'detail service returned no payload for a stack product',
      );
    }
    fetched[id] = (json: jsonEncode(blob), sha256: expectedSha);
  }
  return () async {
    for (final entry in fetched.entries) {
      await userDb.cacheDetail(entry.key, entry.value.json, entry.value.sha256);
    }
  };
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

/// Reads the current detail blob for a product ID.
final detailBlobProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>?, String>((ref, dsldId) async {
      final coreDb = ref.watch(coreDatabaseProvider);
      final product = await coreDb.findById(dsldId);
      if (!ref.mounted || product == null) return null;
      final detail = detailBlobForRowProvider((
        dsldId: dsldId,
        expectedSha: product.detailBlobSha256,
      ));
      // Reconnecting invalidates the ID-based read. Retry a failed hash
      // read as well, while sharing its in-flight work with pinned callers.
      if (ref.read(detail).hasError) ref.invalidate(detail);
      return ref.watch(detail.future);
    }, retry: (_, _) => null);

/// Reads the immutable blob identified by the caller's catalog row.
final detailBlobForRowProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>?, ({String dsldId, String? expectedSha})>(
      (ref, key) async {
        final (:dsldId, :expectedSha) = key;
        final coreDb = ref.watch(coreDatabaseProvider);
        final userDb = ref.watch(userDatabaseProvider);
        final service = ref.watch(detailBlobServiceProvider);
        if (expectedSha == null || expectedSha.isEmpty) return null;
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

        final blob = await service.fetchDetailBlobByHash(expectedSha);
        if (blob == null) {
          throw const DetailBlobUnavailableException(
            'detail service returned no payload for a declared blob',
          );
        }
        // A pinned read can finish after the catalog or account changes.
        // Return its verified bytes, but only the current row owns the
        // single durable cache entry. Serialize the check with cache writes.
        if (ref.mounted) {
          try {
            await userDb.transaction(() async {
              if (!ref.mounted) return;
              final current = await coreDb.findById(dsldId);
              if (!ref.mounted || current?.detailBlobSha256 != expectedSha) {
                return;
              }
              await userDb.cacheDetail(dsldId, jsonEncode(blob), expectedSha);
            });
          } on Object catch (_, trace) {
            // Database exceptions can include statement parameters.
            CrashReportingService().recordError(
              StateError('Could not cache verified catalog detail'),
              trace,
              hint: 'detail_blob:cache_write_failed',
            );
          }
        }
        return blob;
      },
      // Surface an unavailable blob immediately. An explicit refresh or
      // reconnect retries the same content hash.
      retry: (_, _) => null,
    );
