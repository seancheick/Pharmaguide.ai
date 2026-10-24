// Stack-sync queue semantics and the real sender's wire contract.
// Mock HTTP keeps payload verification offline. The PHI release gate also
// checks the column allowlist; debounce has its own focused tests.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/services/connectivity_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UserDatabase db;
  late StackSyncQueue queue;

  setUp(() {
    db = UserDatabase.memory();
    queue = StackSyncQueue(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertRow(
    String id, {
    String type = 'supplement',
    String? dsldId,
    DateTime? syncedAt,
    DateTime? addedAt,
    DateTime? deletedAt,
    DateTime? clientUpdatedAt,
  }) {
    return db
        .into(db.userStacksLocal)
        .insert(
          UserStacksLocalCompanion.insert(
            id: id,
            name: 'Item $id',
            type: Value(type),
            dsldId: Value(dsldId),
            syncedAt: Value(syncedAt),
            addedAt: addedAt == null ? const Value.absent() : Value(addedAt),
            deletedAt: Value(deletedAt),
            clientUpdatedAt: clientUpdatedAt == null
                ? const Value.absent()
                : Value(clientUpdatedAt),
          ),
        );
  }

  test('push sends UTC instants for local stack timestamps', () async {
    const owner = '00000000-0000-0000-0000-000000000001';
    final requests = <Map<String, dynamic>>[];
    final now = DateTime.now().toUtc();
    final tokenClaims = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': owner,
              'exp':
                  now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
                  1000,
            }),
          ),
        )
        .replaceAll('=', '');
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://stack-sync.invalid',
      publishableKey: 'fixture-only',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/v1/token') {
          return http.Response(
            jsonEncode({
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$tokenClaims.fixture',
              'refresh_token': 'fixture-only',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': owner,
                'aud': 'authenticated',
                'created_at': now.toIso8601String(),
                'app_metadata': <String, dynamic>{},
                'user_metadata': <String, dynamic>{},
              },
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        expect(request.url.path, '/rest/v1/user_stacks');
        expect(request.method, 'POST');
        requests.addAll(
          (jsonDecode(request.body) as List).cast<Map<String, dynamic>>(),
        );
        return http.Response(
          '[]',
          201,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(() => Supabase.instance.dispose());
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'fixture@example.invalid',
      password: 'fixture-only',
    );
    final added = DateTime.parse('2026-10-23T20:00:42-04:00').toLocal();
    final updated = DateTime.parse('2026-10-23T20:01:48-04:00').toLocal();
    final deleted = DateTime.parse('2026-10-23T20:02:00-04:00').toLocal();
    expect(
      updated.isUtc,
      isFalse,
      reason: 'exercise the local DateTime wire path',
    );
    await insertRow(
      'deleted',
      dsldId: '1',
      addedAt: added,
      clientUpdatedAt: updated,
      deletedAt: deleted,
    );
    await insertRow(
      'active',
      dsldId: '2',
      addedAt: added,
      clientUpdatedAt: updated,
    );
    final service = StackSyncService(
      queue,
      _SignedInAuth(),
      _OnlineConnectivity(),
      readOwnerUid: () async => owner,
    );
    addTearDown(service.dispose);
    expect(await service.pushAll(force: true), SyncResult.ok);
    expect(requests, hasLength(2));
    for (final row in requests) {
      expect(row['added_at'], '2026-10-24T00:00:42.000Z');
      expect(row['client_updated_at'], '2026-10-24T00:01:48.000Z');
      expect(DateTime.parse(row['client_updated_at'] as String).isUtc, isTrue);
      expect(
        DateTime.parse(
          row['client_updated_at'] as String,
        ).isAtSameMomentAs(updated),
        isTrue,
      );
      expect(
        row['deleted_at'],
        row['id'] == 'deleted' ? '2026-10-24T00:02:00.000Z' : null,
      );
    }
    expect(await queue.pendingCount(), 0);
  });

  group('StackSyncQueue batched sync semantics', () {
    test(
      'dirtyRows excludes medications (PHI) but includes supplements',
      () async {
        await insertRow('supp-1');
        await insertRow('supp-2');
        await insertRow('med-1', type: 'medication');

        final dirty = await queue.dirtyRows();
        expect(dirty.map((r) => r.id), unorderedEquals(['supp-1', 'supp-2']));
        expect(
          dirty.any((r) => r.type == 'medication'),
          isFalse,
          reason: 'medication rows must never reach the sync batch',
        );
      },
    );

    test('markSyncedAll clears the whole pushed batch in one call', () async {
      await insertRow('a');
      await insertRow('b');
      await insertRow('c');
      expect(await queue.pendingCount(), 3);

      final dirty = await queue.dirtyRows();
      await queue.markSyncedAll(dirty);

      expect(
        await queue.pendingCount(),
        0,
        reason: 'all batched rows must flip to synced together',
      );
      for (final id in ['a', 'b', 'c']) {
        expect(await queue.statusOf(id), StackSyncStatus.synced);
      }
    });

    test(
      'markSyncedAll on a failed batch is never called — rows stay dirty',
      () async {
        // Simulates the failure path: the batch upsert threw, so the
        // service skips markSyncedAll entirely. Rows must remain dirty.
        await insertRow('a');
        await insertRow('b');

        expect(await queue.pendingCount(), 2);
        expect(await queue.statusOf('a'), StackSyncStatus.pending);
        expect(await queue.statusOf('b'), StackSyncStatus.pending);
      },
    );

    test('markSyncedAll with an empty list is a no-op', () async {
      await insertRow('a');
      await queue.markSyncedAll(const []);
      expect(await queue.pendingCount(), 1);
    });

    test('markSyncedAll only touches the ids it was given', () async {
      await insertRow('pushed');
      await insertRow('not-pushed');

      final dirty = await queue.dirtyRows();
      final pushed = dirty.where((r) => r.id == 'pushed').toList();
      await queue.markSyncedAll(pushed);

      expect(await queue.statusOf('pushed'), StackSyncStatus.synced);
      expect(await queue.statusOf('not-pushed'), StackSyncStatus.pending);
    });

    test(
      'an integrity failure blocks only the unchanged row; a later edit requeues it',
      () async {
        final originalUpdate = DateTime.utc(2026, 7, 10, 12);
        await insertRow(
          'poison',
          dsldId: '278011',
          clientUpdatedAt: originalUpdate,
        );
        final dirty = await queue.dirtyRows();

        await queue.markBlockedAll(dirty);

        expect(await queue.pendingCount(), 0);
        expect(await queue.statusOf('poison'), StackSyncStatus.blocked);

        await (db.update(
          db.userStacksLocal,
        )..where((t) => t.id.equals('poison'))).write(
          UserStacksLocalCompanion(
            clientUpdatedAt: Value(
              originalUpdate.add(const Duration(minutes: 1)),
            ),
          ),
        );

        expect(await queue.pendingCount(), 1);
        expect(await queue.statusOf('poison'), StackSyncStatus.pending);

        await queue.markSyncedAll(await queue.dirtyRows());
        final row = await (db.select(
          db.userStacksLocal,
        )..where((t) => t.id.equals('poison'))).getSingle();

        expect(await queue.statusOf('poison'), StackSyncStatus.synced);
        expect(row.syncBlockedAt, isNull);
      },
    );

    test(
      'coalesces superseded local rows to the newest product state',
      () async {
        final earlier = DateTime.utc(2026, 7, 10, 12);
        final later = earlier.add(const Duration(minutes: 1));
        await insertRow(
          'deleted-old',
          dsldId: '278011',
          deletedAt: earlier,
          clientUpdatedAt: earlier,
        );
        await insertRow('active-new', dsldId: '278011', clientUpdatedAt: later);

        final batch = buildStackSyncBatch(await queue.dirtyRows());

        expect(batch.representativeRows.map((row) => row.id), ['active-new']);
        expect(
          batch.rowsRepresentedBy('active-new').map((row) => row.id),
          unorderedEquals(['deleted-old', 'active-new']),
        );
      },
    );

    test('uses user and product identity as the remote upsert target', () {
      expect(
        SupabaseContract.userStacksProductConflictTarget,
        'user_id,dsld_id',
      );
    });

    test('a blocked tombstone is not counted as pending deletion', () async {
      final deletedAt = DateTime.utc(2026, 7, 10, 12);
      await insertRow(
        'blocked-delete',
        dsldId: '278011',
        deletedAt: deletedAt,
        clientUpdatedAt: deletedAt,
      );
      final dirty = await queue.dirtyRows();

      await queue.markBlockedAll(dirty);

      expect(await queue.tombstoneRows(), isEmpty);
    });
  });
}

class _SignedInAuth implements AuthStateService {
  @override
  bool get isGuest => false;
  @override
  bool get isSignedIn => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OnlineConnectivity implements ConnectivityService {
  @override
  ConnectionStatus get current => ConnectionStatus.online;
  @override
  void markSyncing() {}
  @override
  void syncComplete() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
