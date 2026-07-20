// FIX (integrity): cached detail blobs must be re-validated against the
// product's CURRENT `detail_blob_sha256` on every read.
//
// Before this fix the provider persisted `sha256 = null` for every cached
// blob and served any fresh (<24h) row unconditionally — so a catalog
// update that re-pointed a product at a new blob kept serving the previous
// snapshot's ingredient/warning JSON, and a poisoned cache row could never
// be detected. [cachedDetailIsServable] is the PURE serve decision; the
// provider wiring tests verify miss → re-fetch → sha persisted.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';

class _FakeBlobService extends DetailBlobService {
  _FakeBlobService(this.blob);

  final Map<String, dynamic>? blob;
  final List<String> requestedHashes = [];

  @override
  Future<Map<String, dynamic>?> fetchDetailBlobByHash(String sha256) async {
    requestedHashes.add(sha256);
    return blob;
  }
}

void main() {
  final now = DateTime(2026, 7, 5, 12);

  group('cachedDetailIsServable (pure cache-serve decision)', () {
    test('fresh cache with matching sha is served', () {
      expect(
        cachedDetailIsServable(
          cachedAt: now.subtract(const Duration(hours: 1)),
          cachedSha256: 'aaa',
          productSha256: 'aaa',
          now: now,
        ),
        isTrue,
      );
    });

    test('fresh cache whose sha differs from the product row is a MISS', () {
      // Catalog OTA re-pointed the product at a new blob: the 24h TTL must
      // NOT keep serving the old snapshot's JSON.
      expect(
        cachedDetailIsServable(
          cachedAt: now.subtract(const Duration(minutes: 5)),
          cachedSha256: 'old-sha',
          productSha256: 'new-sha',
          now: now,
        ),
        isFalse,
      );
    });

    test(
      'legacy null-sha cache row never satisfies a product with a blob hash',
      () {
        // Rows cached before this fix carry sha256 = null; they must be
        // re-fetched (and re-verified) rather than trusted.
        expect(
          cachedDetailIsServable(
            cachedAt: now.subtract(const Duration(minutes: 5)),
            cachedSha256: null,
            productSha256: 'abc',
            now: now,
          ),
          isFalse,
        );
      },
    );

    test('cache older than the TTL is a miss even when the sha matches', () {
      expect(
        cachedDetailIsServable(
          cachedAt: now.subtract(kDetailBlobCacheTtl),
          cachedSha256: 'aaa',
          productSha256: 'aaa',
          now: now,
        ),
        isFalse,
      );
    });

    test('product without a blob hash still serves a legacy cache row', () {
      // Both null → nothing to verify against and nothing to re-fetch;
      // preserving the pre-fix behavior for this corner keeps products
      // that never had a blob from churning.
      expect(
        cachedDetailIsServable(
          cachedAt: now.subtract(const Duration(hours: 1)),
          cachedSha256: null,
          productSha256: null,
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('detailBlobProvider sha wiring', () {
    late CoreDatabase coreDb;
    late UserDatabase userDb;

    setUp(() {
      coreDb = CoreDatabase.memory();
      userDb = UserDatabase.memory();
    });

    tearDown(() async {
      await coreDb.close();
      await userDb.close();
    });

    Future<void> seedProduct(String dsldId, {String? blobSha}) {
      return coreDb
          .into(coreDb.productsCore)
          .insert(
            ProductsCoreCompanion.insert(
              dsldId: dsldId,
              productName: 'Product $dsldId',
              exportVersion: 'test',
              exportedAt: '2026-07-01T00:00:00Z',
              detailBlobSha256: Value(blobSha),
            ),
          );
    }

    ProviderContainer buildContainer(DetailBlobService service) {
      final container = ProviderContainer(
        overrides: [
          coreDatabaseProvider.overrideWithValue(coreDb),
          userDatabaseProvider.overrideWithValue(userDb),
          detailBlobServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'stale-sha cache row triggers a re-fetch and persists the new sha',
      () async {
        await seedProduct('p1', blobSha: 'new-sha');
        // Fresh-by-TTL cache row, but written against the OLD blob.
        await userDb.cacheDetail('p1', jsonEncode({'v': 'old'}), 'old-sha');

        final service = _FakeBlobService({'v': 'new'});
        final container = buildContainer(service);

        final blob = await container.read(detailBlobProvider('p1').future);

        expect(blob, {'v': 'new'});
        expect(
          service.requestedHashes,
          ['new-sha'],
          reason: 'sha mismatch must be treated as a cache miss',
        );

        final cached = await userDb.getCachedDetail('p1');
        expect(
          cached?.sha256,
          'new-sha',
          reason:
              'cacheDetail must persist the verified sha so the row is '
              're-checkable on the next read (never null again)',
        );
        expect(jsonDecode(cached!.blobJson), {'v': 'new'});
      },
    );

    test(
      'legacy null-sha cache row is refreshed for a product with a hash',
      () async {
        await seedProduct('p2', blobSha: 'abc');
        await userDb.cacheDetail('p2', jsonEncode({'v': 'legacy'}), null);

        final service = _FakeBlobService({'v': 'verified'});
        final container = buildContainer(service);

        final blob = await container.read(detailBlobProvider('p2').future);

        expect(blob, {'v': 'verified'});
        expect(service.requestedHashes, ['abc']);
        expect((await userDb.getCachedDetail('p2'))?.sha256, 'abc');
      },
    );

    test(
      'matching fresh cache row is served without any network fetch',
      () async {
        await seedProduct('p3', blobSha: 'same-sha');
        await userDb.cacheDetail('p3', jsonEncode({'v': 'cached'}), 'same-sha');

        final service = _FakeBlobService({'v': 'network'});
        final container = buildContainer(service);

        final blob = await container.read(detailBlobProvider('p3').future);

        expect(blob, {'v': 'cached'});
        expect(
          service.requestedHashes,
          isEmpty,
          reason: 'a verified fresh cache row must not hit the CDN',
        );
      },
    );

    test('fetch failure caches nothing and returns null', () async {
      await seedProduct('p4', blobSha: 'want');
      final service = _FakeBlobService(null); // fetch/verification failed
      final container = buildContainer(service);

      final blob = await container.read(detailBlobProvider('p4').future);

      expect(blob, isNull);
      expect(await userDb.getCachedDetail('p4'), isNull);
    });
  });
}
