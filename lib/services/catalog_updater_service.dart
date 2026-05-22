// CatalogUpdaterService — polls the catalog manifest endpoint and
// stages a downloaded bundle into the `*.staging` slot when the
// remote version is newer than what's installed locally.
//
// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track D, D2.
//
// The service deliberately stops at "validated bundle in staging".
// Activation (the in-session swap that closes the old DB and rebuilds
// the ProviderScope) is the caller's responsibility — see
// `CatalogSwapper` and `_refreshCatalogIfNeeded` in lib/main.dart.
// The split keeps the service stateless and testable in pure Dart
// (no Flutter widget tree, no path_provider, no Supabase client) by
// expressing every external dependency as an injected callback.
//
// The validation gate (PRAGMA integrity_check + version match) lives
// inside `SyncService.stageCoreDbDownload` and runs *before* this
// service returns [CatalogStaged]. A staged file that reaches the
// caller has therefore already cleared schema and corruption checks;
// any further failure must be at activation time, which the swap
// routine handles independently.

import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/services/catalog_version.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

typedef RemoteVersionProbe = Future<String?> Function();
typedef StagedDownload = Future<String> Function({String? expectedVersion});

/// Outcome of a [CatalogUpdaterService.checkForUpdate] call.
sealed class CatalogCheckResult {
  const CatalogCheckResult();
}

/// The probe could not reach the manifest endpoint, or the endpoint
/// returned no current row at all. The caller's installed DB (if any)
/// is unaffected. Retry on the next refresh tick.
class CatalogUnreachable extends CatalogCheckResult {
  final Object? error;
  const CatalogUnreachable({this.error});
}

/// Remote and installed versions match — nothing to download.
class CatalogUpToDate extends CatalogCheckResult {
  final String version;
  const CatalogUpToDate({required this.version});
}

/// A newer bundle was downloaded and validated into the staging slot.
/// The caller now runs the swap routine to activate it in-session.
class CatalogStaged extends CatalogCheckResult {
  final String version;
  const CatalogStaged({required this.version});
}

/// The probe returned a newer version but the download or validation
/// step failed. `SyncService.stageCoreDbDownload` cleans up the
/// partial staging file before throwing, so no state on disk needs
/// rollback.
class CatalogStageFailed extends CatalogCheckResult {
  final Object error;
  final String reason;
  const CatalogStageFailed({required this.error, required this.reason});
}

class CatalogUpdaterService {
  final RemoteVersionProbe probeRemoteVersion;
  final StagedDownload stageDownload;

  const CatalogUpdaterService({
    required this.probeRemoteVersion,
    required this.stageDownload,
  });

  /// Convenience factory that wires the production `SyncService`
  /// dependencies. Tests should construct the service directly with
  /// fake callbacks instead of touching this factory.
  factory CatalogUpdaterService.production({SyncService? syncService}) {
    final svc = syncService ?? SyncService();
    return CatalogUpdaterService(
      probeRemoteVersion: svc.fetchCurrentDbVersion,
      stageDownload: svc.stageCoreDbDownload,
    );
  }

  /// Decide whether a catalog update is available, and stage it into
  /// `*.staging` when one is.
  ///
  /// [installedVersion] is the currently-active catalog version (may
  /// be null when there is no DB on disk yet — a first-run state).
  /// [forceDownload] forces a stage-download even when the remote
  /// matches the installed version; used by the retry path.
  Future<CatalogCheckResult> checkForUpdate({
    String? installedVersion,
    bool forceDownload = false,
  }) async {
    final String? remoteVersion;
    try {
      remoteVersion = await probeRemoteVersion();
    } on Object catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        hint: 'catalog_updater:unreachable',
      );
      return CatalogUnreachable(error: e);
    }

    if (remoteVersion == null) {
      return const CatalogUnreachable();
    }

    if (!forceDownload) {
      final remote = CatalogVersion.parse(remoteVersion);
      if (remote == null) {
        return CatalogUnreachable(
          error: FormatException(
            'Malformed remote catalog version',
            remoteVersion,
          ),
        );
      }

      if (installedVersion != null && installedVersion.trim().isNotEmpty) {
        final installed = CatalogVersion.parse(installedVersion);
        if (installed == null) {
          return CatalogUnreachable(
            error: FormatException(
              'Malformed installed catalog version',
              installedVersion,
            ),
          );
        }

        if (remote.compareTo(installed) <= 0) {
          return CatalogUpToDate(version: installedVersion);
        }
      }
    }

    try {
      final validated = await stageDownload(expectedVersion: remoteVersion);
      return CatalogStaged(version: validated);
    } on Object catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        hint: 'catalog_updater:stage_failed',
      );
      return CatalogStageFailed(
        error: e,
        reason: 'stageCoreDbDownload failed: $e',
      );
    }
  }
}
