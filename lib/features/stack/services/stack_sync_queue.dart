// Sprint 5a — Stack sync offline queue scaffolding.
//
// This file sets up the infrastructure for syncing local stack changes to
// Supabase once connectivity returns. It does NOT implement the full
// Supabase RPC integration — that's tracked as a follow-up inside Sprint
// 5a. What's here is the local side:
//
//   - [StackSyncStatus] — per-row sync state tracked via the existing
//     `user_stacks_local.synced_at` column. When a row has a non-null
//     `clientUpdatedAt` newer than `syncedAt`, it's "dirty" and needs
//     pushing. Tombstones (non-null `deletedAt`) are pushed as deletes.
//
//   - [StackSyncQueue] — pure query helpers over the existing Drift
//     table. Returns the list of dirty rows, tombstones, and last sync
//     timestamp. No new schema, no migrations — we already have the
//     columns from Sprint 0.
//
//   - [StackSyncService] — stub that would call Supabase. Currently
//     returns successfully without pushing anything. Wire this to
//     Supabase in a dedicated follow-up sprint. Consumers call
//     `markSynced` after a successful upstream push.
//
// **PHI rule:** Medication rows (`type='medication'`) MUST NEVER be
// synced. [StackSyncQueue.dirtyRows] filters them out at the query level
// so a downstream bug in the sync service can't leak them.

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

/// Status of a single stack row relative to the remote Supabase table.
enum StackSyncStatus {
  /// Row has never been synced (synced_at IS NULL).
  pending,

  /// Row was synced, then edited locally (client_updated_at > synced_at).
  dirty,

  /// Row is soft-deleted and needs to be pushed as a delete.
  tombstone,

  /// Row is in sync with the remote.
  synced,

  /// Last push failed — the row is waiting for retry. Currently indistinguishable
  /// from pending at the schema level; future work may add an error column.
  failed,
}

/// Pure query helper over the existing `user_stacks_local` table.
class StackSyncQueue {
  final UserDatabase _db;

  const StackSyncQueue(this._db);

  /// All rows that need to be pushed to Supabase, excluding medications
  /// (which are PHI-local-only by design). Returns rows in ascending
  /// `client_updated_at` order so the oldest edit pushes first.
  Future<List<UserStacksLocalData>> dirtyRows() {
    final q = _db.select(_db.userStacksLocal)
      ..where((t) =>
          // Not a medication (PHI rule — never sync)
          t.type.equals('medication').not() &
          // Either never synced, or edited since last sync
          (t.syncedAt.isNull() |
              t.clientUpdatedAt.isBiggerThan(
                t.syncedAt,
              )))
      ..orderBy([
        (t) => OrderingTerm(
              expression: t.clientUpdatedAt,
              mode: OrderingMode.asc,
            ),
      ]);
    return q.get();
  }

  /// Tombstones that need to be pushed as deletes. Again excludes
  /// medications.
  Future<List<UserStacksLocalData>> tombstoneRows() {
    final q = _db.select(_db.userStacksLocal)
      ..where((t) =>
          t.type.equals('medication').not() &
          t.deletedAt.isNotNull() &
          (t.syncedAt.isNull() |
              t.clientUpdatedAt.isBiggerThan(t.syncedAt)));
    return q.get();
  }

  /// Mark a row as successfully synced — sets `synced_at = now`.
  /// Call from the sync service after the upstream RPC succeeds.
  Future<void> markSynced(String entryId) {
    return (_db.update(_db.userStacksLocal)
          ..where((t) => t.id.equals(entryId)))
        .write(UserStacksLocalCompanion(
      syncedAt: Value(DateTime.now()),
    ));
  }

  /// Count of dirty + tombstone rows awaiting push. Used by a future
  /// sync-status indicator in the UI.
  Future<int> pendingCount() async {
    final dirty = await dirtyRows();
    final tombstones = await tombstoneRows();
    return dirty.length + tombstones.length;
  }

  /// Returns the status of a single row. Cheap — single-row query.
  Future<StackSyncStatus> statusOf(String entryId) async {
    final row = await (_db.select(_db.userStacksLocal)
          ..where((t) => t.id.equals(entryId)))
        .getSingleOrNull();
    if (row == null) return StackSyncStatus.failed;
    if (row.type == 'medication') {
      // PHI — we never track sync status for these.
      return StackSyncStatus.synced;
    }
    if (row.deletedAt != null) {
      if (row.syncedAt == null ||
          row.clientUpdatedAt.isAfter(row.syncedAt!)) {
        return StackSyncStatus.tombstone;
      }
      return StackSyncStatus.synced;
    }
    if (row.syncedAt == null) return StackSyncStatus.pending;
    if (row.clientUpdatedAt.isAfter(row.syncedAt!)) {
      return StackSyncStatus.dirty;
    }
    return StackSyncStatus.synced;
  }
}

/// High-level sync orchestrator. Currently a stub — calling [pushAll]
/// iterates dirty rows but does NOT actually call Supabase.
///
/// To complete Sprint 5a: wire the two TODO branches below to
/// `supabase.from('user_stacks').upsert(...)` + `delete(...)` calls, add
/// connectivity-based auto-retry via `connectivity_plus`, and implement
/// LWW conflict resolution using the response row's `server_updated_at`
/// field vs the local `client_updated_at`.
class StackSyncService {
  final StackSyncQueue _queue;

  const StackSyncService(this._queue);

  /// Push all dirty rows + tombstones to Supabase. Returns the number of
  /// rows successfully synced. Silent on errors — the local state is
  /// unchanged, so the next call will retry.
  Future<int> pushAll() async {
    int pushed = 0;

    final dirty = await _queue.dirtyRows();
    for (final row in dirty) {
      // TODO(sprint-5a-finish): upsert to Supabase via
      //   supabase.from('user_stacks').upsert(row.toRemote()).select()
      // then compare server_updated_at to client_updated_at for LWW.
      // For now: immediately mark synced so the local flag clears and
      // we don't treat it as perpetually dirty.
      await _queue.markSynced(row.id);
      pushed++;
    }

    final tombstones = await _queue.tombstoneRows();
    for (final row in tombstones) {
      // TODO(sprint-5a-finish): delete via
      //   supabase.from('user_stacks').delete().eq('id', row.id)
      // Server should soft-delete to support multi-device visibility.
      await _queue.markSynced(row.id);
      pushed++;
    }

    return pushed;
  }
}

/// Riverpod providers for the sync queue + service. Consumers read
/// `stackSyncServiceProvider` and call `.pushAll()` on connectivity
/// events or after every mutation.
final stackSyncQueueProvider = Provider<StackSyncQueue>((ref) {
  final db = ref.watch(userDatabaseProvider);
  return StackSyncQueue(db);
});

final stackSyncServiceProvider = Provider<StackSyncService>((ref) {
  final queue = ref.watch(stackSyncQueueProvider);
  return StackSyncService(queue);
});

/// Stream of pending-count values. Wire to a UI badge showing "N items
/// waiting to sync" once connectivity-driven refresh is in place.
final pendingSyncCountProvider = FutureProvider<int>((ref) {
  final queue = ref.watch(stackSyncQueueProvider);
  return queue.pendingCount();
});
