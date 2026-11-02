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
/// [CoreDatabase] after applying [newDb] via setState. Once its file moves, the
/// old handle fails or keeps reading the old file, depending on the platform. It
/// never returns the new catalog, so the caller should adopt [newDb] straight
/// away.
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
/// When [previousHandleInvalid] is true the caller's open handle can't be
/// trusted any more: on macOS SQLite fails reads with a disk I/O error once a
/// handle's file has been moved, even after it is moved back. The caller must
/// adopt [restoredDb] (and owns closing it) in place of its current handle or,
/// when that is null, stop using the handle and report the catalog unavailable.
class SwapRolledBack extends SwapResult {
  final Object error;
  final String reason;
  final CoreDatabase? restoredDb;
  final String? restoredVersion;
  final bool previousHandleInvalid;
  const SwapRolledBack({
    required this.error,
    required this.reason,
    this.restoredDb,
    this.restoredVersion,
    this.previousHandleInvalid = false,
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
  ///   3. Refuse a staged file that isn't [expectedVersion], before anything
  ///      moves.
  ///   4. Run the activator (atomic rename, keeping a backup).
  ///   5. Require [expectedVersion] of the file now live, restoring the backup
  ///      if it is anything else. This comes first because the next step
  ///      retires the backup of any file that validates.
  ///   6. Open the new DB via [opener], which restores the backup if the new
  ///      file doesn't validate.
  ///   7. Validate via `db.validateCatalogSnapshot()`, and require
  ///      [expectedVersion]: any other version means the update was rolled
  ///      back, and the caller must not treat it as an update. Any failure from
  ///      here on tries a fresh open, because the caller's handle no longer
  ///      works.
  ///   8. Return [SwapSuccess] — caller closes the old DB.
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

    // Persist the versions before activation: even a failed restore followed
    // by process death must not make a refused file trusted on the next boot.
    try {
      await recordCatalogActivation(
        dbPath: dbPath,
        expectedVersion: expectedVersion,
        previousVersion: await _readVersion(dbPath),
      );
    } on Object catch (e) {
      return SwapRolledBack(error: e, reason: 'Activation intent failed: $e');
    }

    final stagedVersion = await _readStagedVersion(dbPath);
    if (stagedVersion != null && stagedVersion != expectedVersion) {
      final error = StateError(
        'Staged catalog $stagedVersion instead of $expectedVersion',
      );
      CrashReportingService().recordError(
        error,
        StackTrace.current,
        fatal: true,
        hint: 'catalog_swap:staged_version_mismatch',
      );
      try {
        await File('$dbPath.staging').delete();
        await File('$dbPath.activation.json').delete();
      } on Object {
        // The boot path revalidates anything left behind.
      }
      return SwapRolledBack(error: error, reason: error.message);
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
      return _reopenAfterMove(e, 'Activation failed: $e', expectedVersion);
    }

    final liveVersion = await _readVersion(dbPath);
    if (liveVersion != null && liveVersion != expectedVersion) {
      final error = StateError(
        'Activated catalog $liveVersion instead of $expectedVersion',
      );
      CrashReportingService().recordError(
        error,
        StackTrace.current,
        fatal: true,
        hint: 'catalog_swap:version_mismatch',
      );
      try {
        final backup = File('$dbPath.backup');
        if (await backup.exists()) await backup.rename(dbPath);
      } on Object catch (e, st) {
        CrashReportingService().recordError(
          e,
          st,
          fatal: true,
          hint: 'catalog_swap:restore',
        );
        // Reopening now would adopt the file that was just refused.
        return SwapRolledBack(
          error: error,
          reason: error.message,
          previousHandleInvalid: true,
        );
      }
      return _reopenAfterMove(error, error.message, expectedVersion);
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
      return _reopenAfterMove(e, 'Open failed: $e', expectedVersion);
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
          previousHandleInvalid: true,
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
      return _reopenAfterMove(e, 'Validation failed: $e', expectedVersion);
    }
  }

  /// The live file may have moved, so the caller's handle is finished either
  /// way. One fresh open decides whether it gets a replacement, which is the
  /// update itself when only the first open failed.
  Future<SwapResult> _reopenAfterMove(
    Object error,
    String reason,
    String expectedVersion,
  ) async {
    CoreDatabase? reopened;
    try {
      reopened = await opener();
      final version = await reopened.validateCatalogSnapshot();
      if (version == expectedVersion) {
        return SwapSuccess(newDb: reopened, version: version);
      }
      return SwapRolledBack(
        error: error,
        reason: reason,
        restoredDb: reopened,
        restoredVersion: version,
        previousHandleInvalid: true,
      );
    } on Object {
      try {
        await reopened?.close();
      } on Object {
        // Best-effort cleanup; nothing actionable for the caller.
      }
      return SwapRolledBack(
        error: error,
        reason: reason,
        previousHandleInvalid: true,
      );
    }
  }

  /// The staged file's version, or null when it can't be read yet: a partial
  /// download keeps its marker, and activation owns refusing an invalid file.
  Future<String?> _readStagedVersion(String dbPath) async {
    final stagingPath = '$dbPath.staging';
    if (await File('$stagingPath.version').exists()) return null;
    return _readVersion(stagingPath);
  }

  /// The version inside the catalog at [path], or null when there is no file or
  /// it doesn't validate. [opener] owns what happens to an invalid live file.
  Future<String?> _readVersion(String path) async {
    if (!await File(path).exists()) return null;
    CoreDatabase? db;
    try {
      db = CoreDatabase.open(path);
      return await db.validateCatalogSnapshot();
    } on Object {
      return null;
    } finally {
      try {
        await db?.close();
      } on Object {
        // Best-effort; the answer above is what matters.
      }
    }
  }
}
