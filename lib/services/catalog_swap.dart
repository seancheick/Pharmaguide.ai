// In-session catalog swap routine. Activates a staged catalog file and
// opens a fresh validated [CoreDatabase] without requiring an app
// relaunch. The caller is responsible for closing the old DB after
// applying the result via setState + ProviderScope rebuild.
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 0, T0.6.
//
// The class is dependency-injected so unit tests can pass simple fake
// callbacks for the path lookup, file activation, and DB opener
// without spinning up `path_provider` or Supabase.

import 'dart:io';

import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

typedef CorePathProvider = Future<String> Function();
typedef CoreDbActivator = Future<void> Function();
typedef CoreDbOpener = Future<CoreDatabase> Function();

/// Outcome of a [CatalogSwapper.swap] call.
sealed class SwapResult {
  const SwapResult();
}

/// Successful in-session swap. The caller MUST close the previously-live
/// [CoreDatabase] after applying [newDb] via setState — the swap routine
/// deliberately does NOT close the old instance because Drift's open
/// connection pins the (now-unlinked) previous file inode and lets any
/// in-flight queries finish cleanly.
class SwapSuccess extends SwapResult {
  final CoreDatabase newDb;
  final String version;
  const SwapSuccess({required this.newDb, required this.version});
}

/// No staging file existed. The caller's current DB is unaffected.
class SwapNoStaging extends SwapResult {
  const SwapNoStaging();
}

/// Swap failed at activation, open, or validation. The previous catalog is
/// back at the live path — `SyncService.activateStagedCoreDbIfPresent` restores
/// the backup on rename failure, `openCoreDatabase` restores it when the new
/// file doesn't validate.
///
/// The caller's open handle can't be trusted any more: SQLite fails reads with
/// a disk I/O error once a handle's file has been moved, even after it is moved
/// back. When [restoredDb] is set the caller must adopt it (and owns closing
/// it) in place of its current handle.
class SwapRolledBack extends SwapResult {
  final Object error;
  final String reason;
  final CoreDatabase? restoredDb;
  final String? restoredVersion;
  const SwapRolledBack({
    required this.error,
    required this.reason,
    this.restoredDb,
    this.restoredVersion,
  });
}

/// Atomically swap a staged catalog file into the live path and open a
/// validated [CoreDatabase] against it.
class CatalogSwapper {
  final CorePathProvider corePathProvider;
  final CoreDbActivator activator;
  final CoreDbOpener opener;

  const CatalogSwapper({
    required this.corePathProvider,
    required this.activator,
    required this.opener,
  });

  /// Convenience wrapper that wires up the production
  /// [SyncService] + [openCoreDatabase] dependencies.
  factory CatalogSwapper.production({SyncService? syncService}) {
    final svc = syncService ?? SyncService();
    return CatalogSwapper(
      corePathProvider: svc.getCoreDbPath,
      activator: svc.activateStagedCoreDbIfPresent,
      opener: openCoreDatabase,
    );
  }

  /// Activate the staged catalog file in-session.
  ///
  /// Sequence (each step is fail-soft — any error → [SwapRolledBack]):
  ///   1. Look up the live DB path.
  ///   2. Bail with [SwapNoStaging] if no staging file exists.
  ///   3. Run the activator (atomic rename, keeping a backup).
  ///   4. Open the new DB via [opener], which restores the backup if the new
  ///      file doesn't validate.
  ///   5. Validate via `db.validateCatalogSnapshot()`, and require
  ///      [expectedVersion]: any other version means the update was rolled
  ///      back, and the caller must not treat it as an update. On failure,
  ///      close the opened DB before returning so we don't leak a connection.
  ///   6. Return [SwapSuccess] — caller closes the old DB.
  Future<SwapResult> swap({required String expectedVersion}) async {
    final String dbPath;
    try {
      dbPath = await corePathProvider();
    } on Object catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        fatal: true,
        hint: 'catalog_swap:path_lookup',
      );
      return SwapRolledBack(error: e, reason: 'Path lookup failed: $e');
    }

    try {
      if (!await File('$dbPath.staging').exists()) {
        return const SwapNoStaging();
      }
    } on Object catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        fatal: true,
        hint: 'catalog_swap:staging_probe',
      );
      return SwapRolledBack(error: e, reason: 'Staging probe failed: $e');
    }

    try {
      await activator();
    } on Object catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        fatal: true,
        hint: 'catalog_swap:activation',
      );
      CoreDatabase? reopened;
      try {
        reopened = await opener();
        return SwapRolledBack(
          error: e,
          reason: 'Activation failed: $e',
          restoredDb: reopened,
          restoredVersion: await reopened.validateCatalogSnapshot(),
        );
      } on Object {
        try {
          await reopened?.close();
        } on Object {
          // Best-effort cleanup; nothing actionable for the caller.
        }
        return SwapRolledBack(error: e, reason: 'Activation failed: $e');
      }
    }

    final CoreDatabase newDb;
    try {
      newDb = await opener();
    } on Object catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        fatal: true,
        hint: 'catalog_swap:open',
      );
      return SwapRolledBack(error: e, reason: 'Open failed: $e');
    }

    try {
      final version = await newDb.validateCatalogSnapshot();
      if (version != expectedVersion) {
        final error = StateError(
          'Opened catalog $version instead of $expectedVersion',
        );
        CrashReportingService().recordError(
          error,
          StackTrace.current,
          fatal: true,
          hint: 'catalog_swap:version_mismatch',
        );
        return SwapRolledBack(
          error: error,
          reason: error.message,
          restoredDb: newDb,
          restoredVersion: version,
        );
      }
      return SwapSuccess(newDb: newDb, version: version);
    } on Object catch (e, st) {
      // Best-effort close. Drift's `close()` can throw when the
      // underlying connection is already broken, but if we let that
      // secondary error propagate we'd lose the original validation
      // failure — which is the cause the caller actually needs to
      // attach to Sentry. Swallow the close error and surface the
      // original `e` in the rollback result.
      try {
        await newDb.close();
      } on Object {
        // Best-effort cleanup; nothing actionable for the caller.
      }
      CrashReportingService().recordError(
        e,
        st,
        fatal: true,
        hint: 'catalog_swap:validation',
      );
      return SwapRolledBack(error: e, reason: 'Validation failed: $e');
    }
  }
}
