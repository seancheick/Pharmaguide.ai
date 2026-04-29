// Sprint 5a — Stack Supabase sync.
//
// What lives here:
// - [StackSyncStatus]   — per-row state classification
// - [StackSyncQueue]    — pure Drift query helpers (dirty / tombstone / count)
// - [StackSyncService]  — real Supabase `upsert` push for signed-in users
// - [StackSyncListener] — auth + connectivity-driven auto-sync
// - Riverpod providers that wire the above into the widget tree
//
// ## PHI rule (non-negotiable)
// Medication rows (`type='medication'`) MUST NEVER leave the device.
// Enforced at THREE layers:
//   1. `StackSyncQueue.dirtyRows()` filters them out at the query level
//   2. `StackSyncService.pushAll()` asserts `row.type == 'supplement'`
//      before pushing (belt and suspenders)
//   3. Supabase `user_stacks` table has a CHECK (type = 'supplement')
//      constraint and an RLS policy `users_can_insert_own_supplements`
//      that rejects anything else. See `supabase/migrations/20260411_user_stacks.sql`.
//
// ## Sync model
// - **Push-only** for Sprint 5a. Pull / multi-device sync is a follow-up.
// - **Offline-first**: every local write succeeds immediately; sync is
//   best-effort and silently retries.
// - **Idempotent**: uses `upsert(onConflict: 'id')` so re-running pushAll
//   with the same dirty set produces no duplicates.
// - **Auth-gated**: guest users skip sync entirely — their stack stays local.
// - **LWW for writes**: whichever client pushes last wins. Pull-sync (when
//   added) will use `server_updated_at` vs `client_updated_at` to detect
//   stale local state.
//
// ## Trigger points
// `StackSyncListener` auto-pushes on:
//   - app startup (if signed in + online)
//   - connectivity transition offline → online
//   - auth transition guest → signed-in
// And `StackActions.addProduct` / `remove` / `restore` fire-and-forget a
// push immediately after their local write.

// Full drift import (no `show` clause) so the extension operators `.not`,
// `|`, and `.isBiggerThan` on Expression/GeneratedColumn resolve. A
// `show` clause would hide the static extensions.
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/services/connectivity_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Sync status
// ---------------------------------------------------------------------------

/// Status of a single stack row relative to the remote Supabase table.
enum StackSyncStatus {
  /// Row has never been synced (`synced_at IS NULL`).
  pending,

  /// Row was synced, then edited locally (`client_updated_at > synced_at`).
  dirty,

  /// Row is soft-deleted and needs to be pushed as a tombstone.
  tombstone,

  /// Row is in sync with the remote.
  synced,

  /// Last push failed — waiting for retry.
  failed,
}

// ---------------------------------------------------------------------------
// Query helper (pure Drift, no network)
// ---------------------------------------------------------------------------

class StackSyncQueue {
  final UserDatabase _db;

  const StackSyncQueue(this._db);

  /// All rows that need to be pushed to Supabase, in ascending
  /// `client_updated_at` order so the oldest edit pushes first.
  ///
  /// Includes both active (updates/inserts) and tombstone (deletes) rows.
  /// Explicitly **excludes** medication rows (PHI — local-only by design).
  Future<List<UserStacksLocalData>> dirtyRows() {
    final q = _db.select(_db.userStacksLocal)
      ..where(
        (t) =>
            // Never sync medications (PHI)
            t.type.equals('medication').not() &
            // Either never synced, or edited since last sync
            (t.syncedAt.isNull() | t.clientUpdatedAt.isBiggerThan(t.syncedAt)),
      )
      ..orderBy([
        (t) =>
            OrderingTerm(expression: t.clientUpdatedAt, mode: OrderingMode.asc),
      ]);
    return q.get();
  }

  /// Just the tombstones that need pushing. Useful for UI counters that
  /// want to show "N pending deletes". Equivalent to filtering [dirtyRows]
  /// but cheaper when only the count is needed.
  Future<List<UserStacksLocalData>> tombstoneRows() {
    final q = _db.select(_db.userStacksLocal)
      ..where(
        (t) =>
            t.type.equals('medication').not() &
            t.deletedAt.isNotNull() &
            (t.syncedAt.isNull() | t.clientUpdatedAt.isBiggerThan(t.syncedAt)),
      );
    return q.get();
  }

  /// Mark a row as successfully synced — sets `synced_at = now`.
  Future<void> markSynced(String entryId) {
    return (_db.update(_db.userStacksLocal)..where((t) => t.id.equals(entryId)))
        .write(UserStacksLocalCompanion(syncedAt: Value(DateTime.now())));
  }

  /// Total count of dirty rows (active + tombstone) awaiting push.
  Future<int> pendingCount() async {
    final dirty = await dirtyRows();
    return dirty.length;
  }

  /// Returns the status of a single row. Cheap — single-row query.
  Future<StackSyncStatus> statusOf(String entryId) async {
    final row = await (_db.select(
      _db.userStacksLocal,
    )..where((t) => t.id.equals(entryId))).getSingleOrNull();
    if (row == null) return StackSyncStatus.failed;
    if (row.type == 'medication') {
      // PHI — we never track sync status for these.
      return StackSyncStatus.synced;
    }
    if (row.deletedAt != null) {
      if (row.syncedAt == null || row.clientUpdatedAt.isAfter(row.syncedAt!)) {
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

// ---------------------------------------------------------------------------
// Sync service — real Supabase push
// ---------------------------------------------------------------------------

/// Result of a [StackSyncService.pushAll] call. Reported via
/// [pendingSyncCountProvider] and the optional sync badge UI.
enum SyncResult {
  /// Sync completed — at least one row pushed (may be zero if nothing was
  /// dirty).
  ok,

  /// Skipped because user is not signed in. Guest mode = local-only.
  skippedGuest,

  /// Skipped because device is offline. Will retry on connectivity regain.
  skippedOffline,

  /// Sync crashed with an unexpected error. Rows are left dirty for retry.
  failed,
}

class StackSyncService {
  final StackSyncQueue _queue;
  final AuthStateService _authState;
  final ConnectivityService _connectivity;

  /// Cached reference to the Supabase client. Nullable because
  /// [Supabase.instance.client] throws in debug mode when the placeholder
  /// guard fires (see `supabase_client.dart`). We silently accept that
  /// case and fall back to skipping sync until the client is available.
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } on Object {
      return null;
    }
  }

  StackSyncService(this._queue, this._authState, this._connectivity);

  /// Push all locally-dirty stack rows to Supabase.
  ///
  /// Returns a [SyncResult] describing the outcome. Never throws — errors
  /// are caught and logged via [debugPrint] so the caller can fire-and-
  /// forget.
  ///
  /// When `force: true`, bypasses the offline check — used when we want
  /// to try anyway (e.g. right after a user action in case the status
  /// cache is stale).
  Future<SyncResult> pushAll({bool force = false}) async {
    // Guard 1: auth state. Guest users stay fully local.
    if (!_authState.isSignedIn) {
      return SyncResult.skippedGuest;
    }

    // Guard 2: connectivity. Don't spam Supabase on a known-offline device.
    if (!force && _connectivity.current == ConnectionStatus.offline) {
      return SyncResult.skippedOffline;
    }

    // Guard 3: Supabase client available
    final supabase = _supabase;
    if (supabase == null) return SyncResult.failed;

    final user = supabase.auth.currentUser;
    if (user == null) {
      // Auth state service thinks we're signed in but Supabase disagrees.
      // Resolve to guest — the next auth event will correct this.
      return SyncResult.skippedGuest;
    }

    _connectivity.markSyncing();

    try {
      final dirty = await _queue.dirtyRows();
      if (dirty.isEmpty) {
        _connectivity.syncComplete();
        return SyncResult.ok;
      }

      for (final row in dirty) {
        // Belt-and-suspenders PHI check — never push medications even if
        // the upstream query helper changes someday.
        assert(
          row.type == 'supplement',
          'PHI leak: medication row ${row.id} reached stack sync',
        );
        if (row.type != 'supplement') continue;

        try {
          await supabase
              .from(SupabaseContract.userStacksTable)
              .upsert(_rowToRemote(row, user.id), onConflict: 'id');
          await _queue.markSynced(row.id);
        } on PostgrestException catch (e) {
          // Leave synced_at alone — row stays dirty, next cycle will retry.
          debugPrint(
            'StackSync upsert failed for ${row.id}: '
            '${e.code} ${e.message}',
          );
        } on Object catch (e) {
          debugPrint('StackSync unexpected error for ${row.id}: $e');
        }
      }

      return SyncResult.ok;
    } on Object catch (e) {
      debugPrint('StackSync pushAll crashed: $e');
      return SyncResult.failed;
    } finally {
      _connectivity.syncComplete();
    }
  }

  /// Map a local stack row to the remote Supabase shape. Injects the
  /// authenticated user id and converts Dart DateTimes to ISO-8601.
  Map<String, dynamic> _rowToRemote(UserStacksLocalData row, String userId) {
    return {
      'id': row.id,
      'user_id': userId,
      'type': row.type, // Always 'supplement' at this point
      'name': row.name,
      'dsld_id': row.dsldId,
      'ingredient_keys': row.ingredientKeys,
      'dosage': row.dosage,
      'frequency': row.frequency,
      'added_at': row.addedAt.toIso8601String(),
      'client_updated_at': row.clientUpdatedAt.toIso8601String(),
      'deleted_at': row.deletedAt?.toIso8601String(),
    };
  }
}

// ---------------------------------------------------------------------------
// Auto-sync listener — auth + connectivity driven
// ---------------------------------------------------------------------------

/// Bootstraps a listener that auto-syncs the stack when:
///   - The app transitions from guest to signed-in
///   - Connectivity comes back online while signed-in
///
/// Consumed as a fire-and-forget provider — widget trees don't read its
/// value, they just ensure `ref.read(stackSyncListenerProvider)` is called
/// once at app startup so the subscriptions are wired up.
final stackSyncListenerProvider = Provider<void>((ref) {
  // Keep this provider alive for the lifetime of the app. Otherwise
  // Riverpod would dispose it as soon as no one reads it, which would
  // tear down the listeners we just set up.
  ref.keepAlive();

  void tryPush() {
    final service = ref.read(stackSyncServiceProvider);
    // Fire-and-forget — errors are logged internally.
    // ignore: discarded_futures
    service.pushAll();
  }

  // React to connectivity transitions. Only push when we've just come
  // back online (edge-trigger, not level-trigger).
  ref.listen<AsyncValue<ConnectionStatus>>(connectionStatusProvider, (
    prev,
    next,
  ) {
    final prevStatus = prev?.valueOrNull;
    final nextStatus = next.valueOrNull;
    if (nextStatus == ConnectionStatus.online &&
        prevStatus != ConnectionStatus.online) {
      tryPush();
    }
  });

  // React to sign-in (guest → signedIn). Brand-new signed-in users will
  // have everything they did as a guest queued up as dirty rows; this
  // pushes all of them at once.
  ref.listen<AuthMode>(authStateProvider, (prev, next) {
    if (prev == AuthMode.guest && next == AuthMode.signedIn) {
      tryPush();
    }
  });

  // Initial push on listener setup — catches the "app started, already
  // signed in, online" case.
  Future.microtask(tryPush);
});

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

final stackSyncQueueProvider = Provider<StackSyncQueue>((ref) {
  final db = ref.watch(userDatabaseProvider);
  return StackSyncQueue(db);
});

final stackSyncServiceProvider = Provider<StackSyncService>((ref) {
  final queue = ref.watch(stackSyncQueueProvider);
  final authState = ref.watch(authStateProvider.notifier);
  final connectivity = ref.watch(connectivityServiceProvider);
  return StackSyncService(queue, authState, connectivity);
});

/// Stream of pending-count values. Wire to a UI badge showing "N items
/// waiting to sync" once you build that indicator. Re-reads on each
/// provider invalidation — not a stream, so bump manually after mutations
/// if you need live updates (or use a StreamProvider if you want continuous).
final pendingSyncCountProvider = FutureProvider<int>((ref) {
  final queue = ref.watch(stackSyncQueueProvider);
  return queue.pendingCount();
});
