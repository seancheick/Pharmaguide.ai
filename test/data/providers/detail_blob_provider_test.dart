// FIX (integrity): cached detail blobs must be re-validated against the
// product's CURRENT `detail_blob_sha256` on every read.
//
// Before this fix the provider persisted `sha256 = null` for every cached
// blob and served any recent row unconditionally — so a catalog
// update that re-pointed a product at a new blob kept serving the previous
// snapshot's ingredient/warning JSON, and a poisoned cache row could never
// be detected. [cachedDetailIsServable] is the PURE serve decision; the
// provider wiring tests verify miss → re-fetch → sha persisted.

import 'dart:async';
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

class _PendingBlobService extends DetailBlobService {
  final requests = <String, Completer<Map<String, dynamic>?>>{};

  @override
  Future<Map<String, dynamic>?> fetchDetailBlobByHash(String sha256) =>
      requests.putIfAbsent(sha256, Completer.new).future;
}

void main() {
  group('cachedDetailIsServable (pure cache-serve decision)', () {
    test('cache with matching sha is served', () {
      expect(
        cachedDetailIsServable(cachedSha256: 'aaa', productSha256: 'aaa'),
        isTrue,
      );
    });

    test('cache whose sha differs from the product row is a MISS', () {
      // Catalog OTA re-pointed the product at a new blob: the old snapshot's
      // JSON must NOT keep being served.
      expect(
        cachedDetailIsServable(
          cachedSha256: 'old-sha',
          productSha256: 'new-sha',
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
          cachedDetailIsServable(cachedSha256: null, productSha256: 'abc'),
          isFalse,
        );
      },
    );

    test('a product without a blob hash has nothing to verify against', () {
      expect(
        cachedDetailIsServable(cachedSha256: null, productSha256: null),
        isFalse,
      );
      expect(
        cachedDetailIsServable(cachedSha256: '', productSha256: ''),
        isFalse,
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
      'pinned rows keep their blobs across an in-flight catalog switch',
      () async {
        await seedProduct('p1', blobSha: 'old-sha');
        final oldRow = (await coreDb.findById('p1'))!;
        final service = _PendingBlobService();
        final container = buildContainer(service);
        final oldProvider = detailBlobForRowProvider((
          dsldId: oldRow.dsldId,
          expectedSha: oldRow.detailBlobSha256,
        ));
        final oldSub = container.listen(oldProvider, (_, _) {});
        addTearDown(oldSub.close);
        final oldBlob = container.read(oldProvider.future);

        await (coreDb.update(
          coreDb.productsCore,
        )..where((row) => row.dsldId.equals('p1'))).write(
          const ProductsCoreCompanion(detailBlobSha256: Value('new-sha')),
        );
        final newRow = (await coreDb.findById('p1'))!;
        final newProvider = detailBlobForRowProvider((
          dsldId: newRow.dsldId,
          expectedSha: newRow.detailBlobSha256,
        ));
        final newSub = container.listen(newProvider, (_, _) {});
        addTearDown(newSub.close);
        final newBlob = container.read(newProvider.future);

        service.requests.putIfAbsent('new-sha', Completer.new).complete({
          'v': 'new',
        });
        expect(await newBlob, {'v': 'new'});
        service.requests.putIfAbsent('old-sha', Completer.new).complete({
          'v': 'old',
        });
        expect(await oldBlob, {'v': 'old'});
        expect(newSub.read().requireValue, {'v': 'new'});
        expect((await userDb.getCachedDetail('p1'))?.sha256, 'new-sha');

        final offlineService = _FakeBlobService(null);
        final reopened = buildContainer(offlineService);
        expect(await reopened.read(newProvider.future), {'v': 'new'});
        expect(offlineService.requestedHashes, isEmpty);
      },
    );

    test(
      'stale-sha cache row triggers a re-fetch and persists the new sha',
      () async {
        await seedProduct('p1', blobSha: 'new-sha');
        // Cache row written against the OLD blob.
        await userDb.cacheDetail('p1', jsonEncode({'v': 'old'}), 'old-sha');

        final service = _FakeBlobService({'v': 'new'});
        final container = buildContainer(service);

        final blob = await container.read(detailBlobProvider('p1').future);

        expect(blob, {'v': 'new'});
        expect(service.requestedHashes, [
          'new-sha',
        ], reason: 'sha mismatch must be treated as a cache miss');

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
      'a verified row is still served after 30 days without any network',
      () async {
        await seedProduct('old', blobSha: 'same-sha');
        await userDb
            .into(userDb.detailCache)
            .insert(
              DetailCacheCompanion(
                dsldId: const Value('old'),
                blobJson: Value(jsonEncode({'v': 'cached'})),
                sha256: const Value('same-sha'),
                cachedAt: Value(
                  DateTime.now().subtract(const Duration(days: 30)),
                ),
              ),
            );

        final service = _FakeBlobService(null);
        final container = buildContainer(service);

        final blob = await container.read(detailBlobProvider('old').future);

        expect(blob, {'v': 'cached'});
        expect(service.requestedHashes, isEmpty);
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
      'a legacy row for a product no longer in the catalog is not served',
      () async {
        await userDb.cacheDetail('gone', jsonEncode({'v': 'legacy'}), null);

        final container = buildContainer(_FakeBlobService(null));

        expect(await container.read(detailBlobProvider('gone').future), isNull);
      },
    );

    for (final (name, sha) in [('null', null), ('empty', '')]) {
      test('a product with a $name hash serves no cached row', () async {
        await seedProduct('hashless', blobSha: sha);
        await userDb.cacheDetail('hashless', jsonEncode({'v': 'legacy'}), sha);

        final service = _FakeBlobService(null);
        final container = buildContainer(service);

        expect(
          await container.read(detailBlobProvider('hashless').future),
          isNull,
        );
        expect(service.requestedHashes, isEmpty);
      });
    }

    test('matching cache row is served without any network fetch', () async {
      await seedProduct('p3', blobSha: 'same-sha');
      await userDb.cacheDetail('p3', jsonEncode({'v': 'cached'}), 'same-sha');

      final service = _FakeBlobService({'v': 'network'});
      final container = buildContainer(service);

      final blob = await container.read(detailBlobProvider('p3').future);

      expect(blob, {'v': 'cached'});
      expect(
        service.requestedHashes,
        isEmpty,
        reason: 'a verified cache row must not hit the CDN',
      );
    });

    test(
      'fetch failure caches nothing and remains an unavailable error',
      () async {
        await seedProduct('p4', blobSha: 'want');
        final service = _FakeBlobService(null); // fetch/verification failed
        final container = buildContainer(service);
        final subscription = container.listen(
          detailBlobProvider('p4'),
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);

        await expectLater(
          container.read(detailBlobProvider('p4').future),
          throwsA(isA<DetailBlobUnavailableException>()),
        );

        expect(service.requestedHashes, [
          'want',
        ], reason: 'unavailable clinical data must not retry invisibly');
        expect(await userDb.getCachedDetail('p4'), isNull);
      },
    );

    group('fetchStackDetailForRelease', () {
      Future<void> addToStack(String id) => userDb.addToStack(
        UserStacksLocalCompanion.insert(
          id: 'stack-$id',
          name: id,
          dsldId: Value(id),
        ),
      );

      test('fetches first and stores only when the release says so', () async {
        await seedProduct('p1', blobSha: 'new-sha');
        await addToStack('p1');
        await userDb.cacheDetail('p1', jsonEncode({'v': 'old'}), 'old-sha');
        final service = _FakeBlobService({'v': 'new'});

        final store = await fetchStackDetailForRelease(
          candidate: coreDb,
          userDb: userDb,
          service: service,
        );

        expect(service.requestedHashes, ['new-sha']);
        expect(
          (await userDb.getCachedDetail('p1'))!.sha256,
          'old-sha',
          reason: 'the phone is still on the old release until the swap',
        );

        await store();
        expect((await userDb.getCachedDetail('p1'))!.sha256, 'new-sha');
      });

      test(
        'a blob that matches the new release is not fetched again',
        () async {
          await seedProduct('p1', blobSha: 'same-sha');
          await addToStack('p1');
          await userDb.cacheDetail('p1', jsonEncode({'v': 'kept'}), 'same-sha');
          final service = _FakeBlobService({'v': 'new'});

          final store = await fetchStackDetailForRelease(
            candidate: coreDb,
            userDb: userDb,
            service: service,
          );
          await store();

          expect(service.requestedHashes, isEmpty);
          expect(jsonDecode((await userDb.getCachedDetail('p1'))!.blobJson), {
            'v': 'kept',
          });
        },
      );

      test('a missing blob stops the update and stores nothing', () async {
        await seedProduct('p1', blobSha: 'sha-1');
        await seedProduct('p2', blobSha: 'sha-2');
        await addToStack('p1');
        await addToStack('p2');

        await expectLater(
          fetchStackDetailForRelease(
            candidate: coreDb,
            userDb: userDb,
            service: _FakeBlobService(null),
          ),
          throwsA(isA<DetailBlobUnavailableException>()),
        );
        expect(await userDb.getCachedDetail('p1'), isNull);
        expect(await userDb.getCachedDetail('p2'), isNull);
      });

      test('an empty stack fetches nothing', () async {
        final service = _FakeBlobService({'v': 'new'});
        final store = await fetchStackDetailForRelease(
          candidate: coreDb,
          userDb: userDb,
          service: service,
        );
        await store();
        expect(service.requestedHashes, isEmpty);
      });
    });
  });
}
