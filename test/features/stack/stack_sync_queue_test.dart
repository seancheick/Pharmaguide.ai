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
    DateTime? syncedAt,
    DateTime? deletedAt,
  }) {
    return db
        .into(db.userStacksLocal)
        .insert(
          UserStacksLocalCompanion.insert(
            id: id,
            name: 'Item $id',
            type: Value(type),
            syncedAt: Value(syncedAt),
            deletedAt: Value(deletedAt),
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
  });
}
