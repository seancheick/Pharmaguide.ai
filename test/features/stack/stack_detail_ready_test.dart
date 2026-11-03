// A catalog release re-points nearly every product at a new blob (measured at
// 92-100% between recent releases), so a stack is only ready offline if its
// blobs are fetched without waiting for the user to open each product.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/services/connectivity_service.dart';

class _FakeBlobService extends DetailBlobService {
  final failing = <String>{};
  final requested = <String>[];
  var online = true;
  Completer<void>? gate;

  @override
  Future<Map<String, dynamic>?> fetchDetailBlobByHash(String sha256) async {
    requested.add(sha256);
    await gate?.future;
    if (!online || failing.contains(sha256)) {
      throw const DetailBlobUnavailableException('unavailable');
    }
    return {'hash': sha256};
  }
}

void main() {
  late CoreDatabase coreDb;
  late UserDatabase userDb;
  late _FakeBlobService service;
  late StreamController<ConnectionStatus> connection;
  late ProviderContainer container;

  Future<void> seedProduct(String id) => coreDb
      .into(coreDb.productsCore)
      .insert(
        ProductsCoreCompanion.insert(
          dsldId: id,
          productName: id,
          exportVersion: 'test',
          exportedAt: '2026-11-02T00:00:00Z',
          detailBlobSha256: Value('$id-new'),
        ),
      );

  Future<void> addToStack(String id) => userDb.addToStack(
    UserStacksLocalCompanion.insert(
      id: 'stack-$id',
      name: id,
      dsldId: Value(id),
    ),
  );

  Future<void> settle() async {
    await pumpEventQueue(times: 200);
  }

  setUp(() {
    coreDb = CoreDatabase.memory();
    userDb = UserDatabase.memory();
    service = _FakeBlobService();
    connection = StreamController<ConnectionStatus>.broadcast();
    container = ProviderContainer(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        userDatabaseProvider.overrideWithValue(userDb),
        detailBlobServiceProvider.overrideWithValue(service),
        connectionStatusProvider.overrideWith((ref) => connection.stream),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await connection.close();
      await coreDb.close();
      await userDb.close();
    });
  });

  test('a stale blob is replaced without opening the product', () async {
    await seedProduct('a');
    await addToStack('a');
    await userDb.cacheDetail('a', '{"hash":"a-old"}', 'a-old');

    container.listen(stackDetailReadyProvider, (_, _) {});
    await settle();

    expect((await userDb.getCachedDetail('a'))?.sha256, 'a-new');
  });

  test('a blob already on the phone needs no network', () async {
    await seedProduct('a');
    await addToStack('a');
    await userDb.cacheDetail('a', '{"hash":"a-new"}', 'a-new');

    container.listen(stackDetailReadyProvider, (_, _) {});
    await settle();

    expect(service.requested, isEmpty);
  });

  test('one failure does not stop the rest of the stack', () async {
    await seedProduct('a');
    await seedProduct('b');
    await addToStack('a');
    await addToStack('b');
    service.failing.add('a-new');

    container.listen(stackDetailReadyProvider, (_, _) {});
    await settle();

    expect(await userDb.getCachedDetail('a'), isNull);
    expect((await userDb.getCachedDetail('b'))?.sha256, 'b-new');
  });

  test(
    'coming back online finishes the job and clears a shown failure',
    () async {
      await seedProduct('a');
      await addToStack('a');
      service.online = false;
      connection.add(ConnectionStatus.offline);

      final shown = container.listen(detailBlobProvider('a'), (_, _) {});
      container.listen(stackDetailReadyProvider, (_, _) {});
      await settle();
      expect(shown.read().hasError, isTrue);
      expect(await userDb.getCachedDetail('a'), isNull);

      service.online = true;
      connection.add(ConnectionStatus.online);
      await settle();

      expect((await userDb.getCachedDetail('a'))?.sha256, 'a-new');
      expect(shown.read().value, {'hash': 'a-new'});
    },
  );

  test('a connection change during a fetch leaves no error behind', () async {
    await seedProduct('a');
    await seedProduct('b');
    await addToStack('a');
    await addToStack('b');
    final gate = service.gate = Completer<void>();

    container.listen(stackDetailReadyProvider, (_, _) {});
    await settle();
    connection.add(ConnectionStatus.online);
    await settle();
    service.gate = null;
    gate.complete();
    await settle();

    expect((await userDb.getCachedDetail('a'))?.sha256, 'a-new');
    expect((await userDb.getCachedDetail('b'))?.sha256, 'b-new');
  });

  test('a product added later is fetched too', () async {
    await seedProduct('a');
    await seedProduct('b');
    await addToStack('a');

    container.listen(stackDetailReadyProvider, (_, _) {});
    await settle();

    await addToStack('b');
    container.invalidate(activeStackProvider);
    await settle();

    expect((await userDb.getCachedDetail('b'))?.sha256, 'b-new');
  });

  test('a medication or an unknown catalog id fetches nothing', () async {
    await userDb.addToStack(
      UserStacksLocalCompanion.insert(
        id: 'med',
        name: 'med',
        type: const Value('medication'),
      ),
    );
    await addToStack('not-in-catalog');

    container.listen(stackDetailReadyProvider, (_, _) {});
    await settle();

    expect(service.requested, isEmpty);
  });
}
