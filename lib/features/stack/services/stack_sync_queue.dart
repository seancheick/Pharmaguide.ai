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
//      that rejects anything else. See
//      `supabase/migrations/20260710210013_app_data_schema_authority_and_access.sql`.
//
// ## Sync model
// - **Push-only** for Sprint 5a. Pull / multi-device sync is a follow-up.
// - **Offline-first**: every local write succeeds immediately; sync is
//   best-effort and silently retries.
// - **Idempotent**: uses the remote `(user_id, dsld_id)` state key, so a
//   replacement local entry updates the same product rather than duplicating.
// - **Auth-gated**: guest users skip sync entirely — their stack stays local.
// - **LWW for writes**: the database accepts only the newest
//   `client_updated_at` state. Pull-sync (when added) will use
//   server-maintained `updated_at` with `client_updated_at` to detect stale
//   local state.
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
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/utils/async_debouncer.dart';
import 'package:pharmaguide/core/utils/retry.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart'
    show AccountOwnerStore;
import 'package:pharmaguide/services/auth_state_service.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/services/connectivity_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
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

  /// Last push failed — the row remains eligible for retry.
  failed,

  /// A non-retryable integrity failure blocked this exact local version.
  /// A subsequent local edit automatically makes the row eligible again.
  blocked,
}

/// A coalesced remote sync batch. Local soft-delete history can contain more
/// than one dirty row for the same product; only the newest state is sent.
@visibleForTesting
class StackSyncBatch {
  final List<UserStacksLocalData> representativeRows;
  final List<UserStacksLocalData> invalidRows;
  final Map<String, List<UserStacksLocalData>> _rowsByRepresentativeId;

  const StackSyncBatch({
    required this.representativeRows,
    required this.invalidRows,
    required this._rowsByRepresentativeId,
  });

  /// Every local history row superseded by [representativeId]. When the
  /// representative succeeds, each of these rows has been represented by the
  /// remote state and can stop retrying.
  List<UserStacksLocalData> rowsRepresentedBy(String representativeId) {
    return _rowsByRepresentativeId[representativeId] ??
        const <UserStacksLocalData>[];
  }

  List<UserStacksLocalData> rowsRepresentedByAll(
    Iterable<UserStacksLocalData> representatives,
  ) {
    return [
      for (final representative in representatives)
        ...rowsRepresentedBy(representative.id),
    ];
  }

  List<UserStacksLocalData> get allRepresentedRows {
    return rowsRepresentedByAll(representativeRows);
  }
}

/// Collapses local product history to its newest state before a remote batch
/// upsert. This prevents a delete-and-readd cycle from submitting two rows for
/// the same remote `(user_id, dsld_id)` key.
@visibleForTesting
StackSyncBatch buildStackSyncBatch(List<UserStacksLocalData> rows) {
  final rowsByProductId = <String, List<UserStacksLocalData>>{};
  final invalidRows = <UserStacksLocalData>[];

  for (final row in rows) {
    final dsldId = row.dsldId;
    if (dsldId == null || dsldId.trim().isEmpty) {
      invalidRows.add(row);
      continue;
    }
    (rowsByProductId[dsldId] ??= <UserStacksLocalData>[]).add(row);
  }

  final representatives = <UserStacksLocalData>[];
  final rowsByRepresentativeId = <String, List<UserStacksLocalData>>{};
  for (final productRows in rowsByProductId.values) {
    final representative = productRows.reduce((latest, candidate) {
      final isNewer = candidate.clientUpdatedAt.isAfter(latest.clientUpdatedAt);
      final sameInstant = candidate.clientUpdatedAt.isAtSameMomentAs(
        latest.clientUpdatedAt,
      );
      return isNewer || (sameInstant && candidate.id.compareTo(latest.id) > 0)
          ? candidate
          : latest;
    });
    representatives.add(representative);
    rowsByRepresentativeId[representative.id] = productRows;
  }
  representatives.sort(
    (a, b) => a.clientUpdatedAt.compareTo(b.clientUpdatedAt),
  );

  return StackSyncBatch(
    representativeRows: List.unmodifiable(representatives),
    invalidRows: List.unmodifiable(invalidRows),
    rowsByRepresentativeId: Map.unmodifiable(rowsByRepresentativeId),
  );
}

/// SQLSTATE class 23 is an integrity-constraint violation. Repeating the
/// unchanged payload cannot repair it, so pause that local version until the
/// user changes it or an app update changes its data contract.
@visibleForTesting
bool isTerminalStackSyncError(Object error) {
  return error is PostgrestException && (error.code ?? '').startsWith('23');
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
            (t.syncedAt.isNull() | t.clientUpdatedAt.isBiggerThan(t.syncedAt)) &
            // A terminal failure pauses only this exact local version. A
            // later edit has a newer client timestamp and re-enters the queue.
            (t.syncBlockedAt.isNull() |
                t.clientUpdatedAt.isBiggerThan(t.syncBlockedAt)),
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
            (t.syncedAt.isNull() | t.clientUpdatedAt.isBiggerThan(t.syncedAt)) &
            (t.syncBlockedAt.isNull() |
                t.clientUpdatedAt.isBiggerThan(t.syncBlockedAt)),
      );
    return q.get();
  }

  /// Mark a row as successfully synced — sets `synced_at = now`.
  Future<void> markSynced(String entryId) {
    return (_db.update(_db.userStacksLocal)..where((t) => t.id.equals(entryId)))
        .write(UserStacksLocalCompanion(syncedAt: Value(DateTime.now())));
  }

  /// Batch variant of [markSynced] — only called after the batched upsert
  /// succeeds, preserving dirty-until-confirmed semantics.
  ///
  /// `synced_at` is set to each row's `client_updated_at` AS PUSHED (not
  /// `now`): an edit landing between the dirty-row read and this mark
  /// bumps `client_updated_at` past the recorded `synced_at`, so the row
  /// stays dirty and the edit is pushed next cycle (no TOCTOU drop). A
  /// successful push also clears any older terminal-failure marker.
  Future<void> markSyncedAll(List<UserStacksLocalData> pushedRows) {
    if (pushedRows.isEmpty) return Future.value();
    return _db.transaction(() async {
      for (final row in pushedRows) {
        await (_db.update(
          _db.userStacksLocal,
        )..where((t) => t.id.equals(row.id))).write(
          UserStacksLocalCompanion(
            syncedAt: Value(row.clientUpdatedAt),
            syncBlockedAt: const Value(null),
          ),
        );
      }
    });
  }

  /// Pause rows whose unchanged payload cannot recover from a remote
  /// integrity violation. This is deliberately separate from [markSyncedAll]:
  /// the remote write did not succeed and must never be represented as synced.
  Future<void> markBlockedAll(List<UserStacksLocalData> failedRows) {
    if (failedRows.isEmpty) return Future.value();
    return _db.transaction(() async {
      for (final row in failedRows) {
        await (_db.update(
          _db.userStacksLocal,
        )..where((t) => t.id.equals(row.id))).write(
          UserStacksLocalCompanion(syncBlockedAt: Value(row.clientUpdatedAt)),
        );
      }
    });
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
    if (row.syncBlockedAt != null &&
        !row.clientUpdatedAt.isAfter(row.syncBlockedAt!)) {
      return StackSyncStatus.blocked;
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

  /// Skipped because the authenticated uid does not match the durable
  /// local-data owner (see [AccountOwnerStore]). Belt-and-suspenders for
  /// the account-switch clear: a previous user's rows must NEVER upload
  /// under the new user's uid, even if a clear was missed or hasn't
  /// completed yet. Rows stay local until ownership is resolved.
  skippedOwnerMismatch,

  /// Sync failed — the push crashed, or the batched upsert failed and at
  /// least one row of the per-row fallback also failed. Failing rows are
  /// left dirty for retry and the failure is reported non-fatally to
  /// crash reporting (never silently swallowed).
  failed,
}

/// PURE owner gate for the push path: rows may only upload when the
/// durable owner record matches the authenticated uid exactly. A null /
/// empty owner (adoption not stamped yet) also blocks — the sign-in
/// guard stamps it within moments, and blocking the interim push is the
/// safe direction for a medical-data sync.
bool ownerAllowsPush({
  required String? storedOwner,
  required String currentUid,
}) {
  return storedOwner != null &&
      storedOwner.isNotEmpty &&
      storedOwner == currentUid;
}

/// Outcome of the per-row fallback push (see [pushRowsIndividually]).
class PerRowPushOutcome {
  /// Rows whose individual upsert succeeded — safe to mark synced.
  final List<UserStacksLocalData> succeeded;

  /// Rows whose unchanged payload hit a terminal integrity failure and were
  /// paused until their next local edit.
  final List<UserStacksLocalData> blocked;

  /// Number of rows that failed for a potentially transient reason and remain
  /// eligible for the normal retry path.
  final int retryableFailedCount;

  int get failedCount => blocked.length + retryableFailedCount;

  const PerRowPushOutcome({
    required this.succeeded,
    required this.blocked,
    required this.retryableFailedCount,
  });
}

/// Per-row salvage pass for a FAILED batched upsert: one poisoned row
/// (constraint / RLS rejection) must not wedge the whole sync queue
/// forever, so each row is retried individually and only the failing
/// row(s) stay dirty.
///
/// [payload] and [rows] are the index-aligned lists built by
/// `StackSyncService._pushNow` — already PHI-filtered (supplements only);
/// this function never widens that set. Pure orchestration over the
/// injected [upsertRow] (no Supabase types) so the isolation logic is
/// unit-testable; a row failure is reported via [onRowError] and never
/// aborts the remaining rows.
@visibleForTesting
Future<PerRowPushOutcome> pushRowsIndividually({
  required List<Map<String, dynamic>> payload,
  required List<UserStacksLocalData> rows,
  required Future<void> Function(Map<String, dynamic> rowPayload) upsertRow,
  bool Function(Object error) isTerminalFailure = isTerminalStackSyncError,
  void Function(Object error, StackTrace stackTrace, String rowId)? onRowError,
}) async {
  assert(
    payload.length == rows.length,
    'payload/rows must be index-aligned (${payload.length} vs ${rows.length})',
  );
  final succeeded = <UserStacksLocalData>[];
  final blocked = <UserStacksLocalData>[];
  var retryableFailedCount = 0;
  for (var i = 0; i < payload.length && i < rows.length; i++) {
    try {
      await upsertRow(payload[i]);
      succeeded.add(rows[i]);
    } on Object catch (error, stackTrace) {
      if (isTerminalFailure(error)) {
        blocked.add(rows[i]);
      } else {
        retryableFailedCount++;
      }
      onRowError?.call(error, stackTrace, rows[i].id);
    }
  }
  return PerRowPushOutcome(
    succeeded: succeeded,
    blocked: blocked,
    retryableFailedCount: retryableFailedCount,
  );
}

class StackSyncService {
  final StackSyncQueue _queue;
  final AuthStateService _authState;
  final ConnectivityService _connectivity;

  /// Reads the durable local-data owner uid for the push-path owner gate
  /// ([ownerAllowsPush]). Injectable for tests; defaults to the real
  /// [AccountOwnerStore].
  final Future<String?> Function() _readOwnerUid;

  /// Debounce window for [pushAll]: rapid stack mutations (add 3 products
  /// in a row) coalesce into a single batched upsert instead of three
  /// network round-trips. Injectable so tests don't wait wall-clock time.
  final AsyncDebouncer<SyncResult> _debouncer;

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

  StackSyncService(
    this._queue,
    this._authState,
    this._connectivity, {
    Duration debounce = const Duration(milliseconds: 1500),
    Future<String?> Function()? readOwnerUid,
  }) : _readOwnerUid = readOwnerUid ?? _defaultReadOwnerUid,
       _debouncer = AsyncDebouncer<SyncResult>(debounce);

  static Future<String?> _defaultReadOwnerUid() => AccountOwnerStore().read();

  /// Push all locally-dirty stack rows to Supabase.
  ///
  /// Returns a [SyncResult] describing the outcome. Never throws — errors
  /// are caught, logged via [debugPrint], and reported non-fatally to
  /// crash reporting, so the caller can fire-and-forget.
  ///
  /// Debounced: calls within the debounce window coalesce into a single
  /// batched push (all coalesced callers share the same result Future).
  /// The dirty-row set is read at execution time, so every mutation made
  /// before the push runs is included.
  ///
  /// When `force: true`, bypasses both the debounce and the offline
  /// check — used when we want to try right now (e.g. right after a user
  /// action in case the status cache is stale).
  /// Cancel any scheduled debounce run. Call on teardown.
  void dispose() => _debouncer.dispose();

  Future<SyncResult> pushAll({bool force = false}) {
    // Guest users stay fully local — answer immediately instead of
    // scheduling a debounce timer that would never push anything (and
    // would leak a pending Timer past widget-test teardown).
    if (!_authState.isSignedIn) {
      return Future.value(SyncResult.skippedGuest);
    }
    if (force) {
      return _debouncer.runNow(() => _pushNow(force: true));
    }
    return _debouncer.run(_pushNow);
  }

  Future<SyncResult> _pushNow({bool force = false}) async {
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

    // Guard 4: account ownership. Never push rows under a uid that does
    // not own the local data — the account-switch guard normally clears
    // before this can matter, but a launch race or interrupted switch
    // must not cross-upload the previous user's rows (read at execution
    // time so a just-completed adopt/switch is honored).
    final ownerUid = await _readOwnerUid();
    if (!ownerAllowsPush(storedOwner: ownerUid, currentUid: user.id)) {
      debugPrint(
        'StackSync skipped: local-data owner does not match signed-in uid',
      );
      return SyncResult.skippedOwnerMismatch;
    }

    _connectivity.markSyncing();

    try {
      final dirty = await _queue.dirtyRows();
      if (dirty.isEmpty) {
        _connectivity.syncComplete();
        return SyncResult.ok;
      }

      final syncBatch = buildStackSyncBatch(dirty);
      var hasTerminalFailure = false;
      if (syncBatch.invalidRows.isNotEmpty) {
        // Supplements are product-backed. An old/corrupt cache row without a
        // DSLD identity cannot satisfy the remote state key, so do not retry
        // the unchanged payload on every sync trigger.
        await _queue.markBlockedAll(syncBatch.invalidRows);
        hasTerminalFailure = true;
        final error = StateError(
          'StackSync supplement row lacks DSLD identity',
        );
        CrashReportingService().recordError(
          error,
          StackTrace.current,
          fatal: false,
          hint: 'stack_sync:missing_dsld_identity',
        );
      }

      // Build one batched payload instead of a per-row round-trip loop.
      final payload = <Map<String, dynamic>>[];
      final pushedRows = <UserStacksLocalData>[];
      for (final row in syncBatch.representativeRows) {
        // Belt-and-suspenders PHI check — never push medications even if
        // the upstream query helper changes someday.
        assert(
          row.type == 'supplement',
          'PHI leak: medication row ${row.id} reached stack sync',
        );
        if (row.type != 'supplement') continue;

        payload.add(_rowToRemote(row, user.id));
        pushedRows.add(row);
      }

      if (payload.isEmpty) {
        return hasTerminalFailure ? SyncResult.failed : SyncResult.ok;
      }

      try {
        await _traceUserSyncUpsert(
          rowCount: payload.length,
          upsert: () => retryWithBackoff(
            () => supabase
                .from(SupabaseContract.userStacksTable)
                .upsert(
                  payload,
                  onConflict: SupabaseContract.userStacksProductConflictTarget,
                ),
            timeout: const Duration(seconds: 10),
          ),
        );
        // Rows are marked synced ONLY after the batch succeeds. Every local
        // history row represented by this product state is then clean.
        await _queue.markSyncedAll(syncBatch.allRepresentedRows);
      } on Object catch (batchError, batchStack) {
        // The batch is all-or-nothing, so ONE poisoned row (constraint /
        // RLS rejection) would otherwise wedge every other row forever —
        // and before this fallback the failure was debugPrint-only while
        // the method still reported ok. Salvage per-row: healthy rows
        // sync, only the poison row(s) stay dirty, and the cycle reports
        // failed so callers/badges never claim a clean sync.
        debugPrint(
          'StackSync batched upsert failed (${payload.length} rows): '
          '$batchError — falling back to per-row upserts',
        );
        final outcome = await pushRowsIndividually(
          payload: payload,
          rows: pushedRows,
          upsertRow: (rowPayload) => supabase
              .from(SupabaseContract.userStacksTable)
              .upsert(
                rowPayload,
                onConflict: SupabaseContract.userStacksProductConflictTarget,
              )
              .timeout(const Duration(seconds: 10)),
          // Row id only — never the row name/dosage (keep Sentry free of
          // stack contents; the id is an opaque uuid).
          onRowError: (error, stackTrace, rowId) {
            debugPrint('StackSync row upsert failed ($rowId): $error');
            CrashReportingService().recordError(
              error,
              stackTrace,
              fatal: false,
              hint: 'stack_sync:row_upsert_failed',
            );
          },
        );
        await _queue.markSyncedAll(
          syncBatch.rowsRepresentedByAll(outcome.succeeded),
        );
        await _queue.markBlockedAll(
          syncBatch.rowsRepresentedByAll(outcome.blocked),
        );
        if (outcome.failedCount > 0) {
          CrashReportingService().recordError(
            batchError,
            batchStack,
            fatal: false,
            hint: 'stack_sync:batched_upsert_failed',
          );
          // Retryable failures stay dirty. Integrity failures are paused
          // until the local row changes, preventing a poison row from
          // generating a non-fatal crash on every sync trigger.
          return SyncResult.failed;
        }
      }

      return hasTerminalFailure ? SyncResult.failed : SyncResult.ok;
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
    final prevStatus = prev?.value;
    final nextStatus = next.value;
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
  final service = StackSyncService(queue, authState, connectivity);
  // Cancel any scheduled debounce when the container goes away (app
  // teardown / widget-test ProviderScope disposal) so no Timer leaks.
  ref.onDispose(service.dispose);
  return service;
});

/// Stream of pending-count values. Wire to a UI badge showing "N items
/// waiting to sync" once you build that indicator. Re-reads on each
/// provider invalidation — not a stream, so bump manually after mutations
/// if you need live updates (or use a StreamProvider if you want continuous).
final pendingSyncCountProvider = FutureProvider<int>((ref) {
  final queue = ref.watch(stackSyncQueueProvider);
  return queue.pendingCount();
});

Future<void> _traceUserSyncUpsert({
  required int rowCount,
  required Future<void> Function() upsert,
}) async {
  final span = _startUserSyncSpan(rowCount);
  SpanStatus status = const SpanStatus.ok();
  try {
    await upsert();
  } on Object catch (error) {
    status = _userSyncStatusForError(error);
    span?.throwable = error;
    rethrow;
  } finally {
    await _finishUserSyncSpan(span, status);
  }
}

ISentrySpan? _startUserSyncSpan(int rowCount) {
  try {
    final parent = Sentry.getSpan();
    final span =
        parent?.startChild(
          'http.client',
          description: 'Upsert synced supplement rows',
        ) ??
        Sentry.startTransaction(
          'Upsert synced supplement rows',
          'http.client',
          bindToScope: false,
        );
    span
      ..setTag('pg.surface', 'user_sync')
      ..setData('sync.row_count', rowCount)
      ..setData('http.request.method', 'POST');
    return span;
  } on Object {
    return null;
  }
}

Future<void> _finishUserSyncSpan(ISentrySpan? span, SpanStatus status) async {
  if (span == null || span.finished) return;
  await span.finish(status: status);
}

SpanStatus _userSyncStatusForError(Object error) {
  if (error is TimeoutException) return const SpanStatus.deadlineExceeded();
  if (error is PostgrestException) return const SpanStatus.unknownError();
  return const SpanStatus.unknownError();
}
