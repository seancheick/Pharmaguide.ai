// Batched stack-sync queue logic — the pure Drift layer that feeds
// StackSyncService's single batched upsert. The network half is covered
// by the PHI release gate (static) and the debounce by
// test/core/utils/async_debouncer_test.dart; here we verify the
// dirty/synced_at semantics the batch path depends on.

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

  Future<void> insertRow(
    String id, {
    String type = 'supplement',
    String? dsldId,
    DateTime? syncedAt,
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
            deletedAt: Value(deletedAt),
            clientUpdatedAt: clientUpdatedAt == null
                ? const Value.absent()
                : Value(clientUpdatedAt),
          ),
        );
  }

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
      expect(userStackUpsertConflictTarget, 'user_id,dsld_id');
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
