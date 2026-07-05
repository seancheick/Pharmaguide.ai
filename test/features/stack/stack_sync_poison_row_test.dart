// FIX (data-integrity): one poisoned sync row must not wedge stack sync
// forever while reporting success.
//
// StackSyncService._pushNow pushes ONE batched upsert. Before this fix any
// batch failure was debugPrint-only and the method still returned
// SyncResult.ok — so a single bad row (constraint / RLS rejection) kept
// every other row dirty forever, silently (data loss at device
// migration). The fix falls back to per-row upserts
// ([pushRowsIndividually]) so healthy rows still sync, only the poison
// row stays dirty for retry, and the cycle reports SyncResult.failed.
//
// The salvage loop is extracted as a pure orchestration over an injected
// upsert function, so it is fully unit-testable without Supabase.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';

void main() {
  late UserDatabase db;
  late StackSyncQueue queue;

  setUp(() {
    db = UserDatabase.memory();
    queue = StackSyncQueue(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertRow(String id) {
    return db
        .into(db.userStacksLocal)
        .insert(
          UserStacksLocalCompanion.insert(
            id: id,
            name: 'Item $id',
            type: const Value('supplement'),
          ),
        );
  }

  /// Mirrors _pushNow's parallel payload/rows construction.
  Future<(List<UserStacksLocalData>, List<Map<String, dynamic>>)>
  dirtyWithPayload() async {
    final rows = await queue.dirtyRows();
    final payload = [
      for (final row in rows) {'id': row.id, 'name': row.name},
    ];
    return (rows, payload);
  }

  group('pushRowsIndividually (poison-row isolation)', () {
    test('all rows succeeding → all marked pushed, zero failures', () async {
      await insertRow('a');
      await insertRow('b');
      final (rows, payload) = await dirtyWithPayload();

      final outcome = await pushRowsIndividually(
        payload: payload,
        rows: rows,
        upsertRow: (_) async {},
      );

      expect(outcome.succeeded.map((r) => r.id), unorderedEquals(['a', 'b']));
      expect(outcome.failedCount, 0);
    });

    test(
      'a poison row fails ALONE — rows before and after it still push',
      () async {
        await insertRow('a');
        await insertRow('poison');
        await insertRow('c');
        final (rows, payload) = await dirtyWithPayload();

        final failedIds = <String>[];
        final outcome = await pushRowsIndividually(
          payload: payload,
          rows: rows,
          upsertRow: (rowPayload) async {
            if (rowPayload['id'] == 'poison') {
              throw StateError('violates check constraint');
            }
          },
          onRowError: (error, stackTrace, rowId) => failedIds.add(rowId),
        );

        expect(
          outcome.succeeded.map((r) => r.id),
          unorderedEquals(['a', 'c']),
          reason:
              'the loop must continue past the poison row so healthy rows '
              'are not held hostage',
        );
        expect(outcome.failedCount, 1);
        expect(failedIds, ['poison']);
      },
    );

    test('every row failing → nothing succeeded, all counted', () async {
      await insertRow('a');
      await insertRow('b');
      final (rows, payload) = await dirtyWithPayload();

      final outcome = await pushRowsIndividually(
        payload: payload,
        rows: rows,
        upsertRow: (_) async => throw StateError('offline mid-push'),
      );

      expect(outcome.succeeded, isEmpty);
      expect(outcome.failedCount, 2);
    });

    test('empty batch is a harmless no-op', () async {
      final outcome = await pushRowsIndividually(
        payload: const [],
        rows: const [],
        upsertRow: (_) async => fail('must not be called'),
      );
      expect(outcome.succeeded, isEmpty);
      expect(outcome.failedCount, 0);
    });
  });

  group('dirty-row semantics after a partial per-row salvage', () {
    test(
      'healthy rows flip to synced; the poison row stays dirty for retry',
      () async {
        await insertRow('a');
        await insertRow('poison');
        await insertRow('c');
        final (rows, payload) = await dirtyWithPayload();

        final outcome = await pushRowsIndividually(
          payload: payload,
          rows: rows,
          upsertRow: (rowPayload) async {
            if (rowPayload['id'] == 'poison') {
              throw StateError('RLS rejection');
            }
          },
        );
        // What _pushNow does with the outcome: mark ONLY the succeeded
        // subset as synced.
        await queue.markSyncedAll(outcome.succeeded);

        expect(await queue.statusOf('a'), StackSyncStatus.synced);
        expect(
          await queue.statusOf('poison'),
          StackSyncStatus.pending,
          reason: 'the failed row must stay dirty so the next cycle retries',
        );
        expect(await queue.statusOf('c'), StackSyncStatus.synced);
        expect(
          await queue.pendingCount(),
          1,
          reason: 'only the poison row remains queued',
        );
      },
    );
  });
}
