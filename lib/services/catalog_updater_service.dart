// CatalogUpdaterService — reads the current release from the manifest, decides
// whether this phone should take it, and downloads what it needs.
//
// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track D, D2, and ADR-012.
//
// The service stops at "verified files in staging". Activation belongs to
// `ReleaseStore.activate`, and adopting the new handles to `lib/main.dart`.
// The split keeps the decision testable in pure Dart by expressing every
// external dependency as an injected callback.
//
// A build with verification keys takes only signed releases and compares
// release sequences, so a rollback is a republish under a newer sequence. A
// build with no keys ignores signed fields and takes catalog-only updates by
// `db_version`, with the rules it already has.

import 'dart:io';

import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/services/catalog_version.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/release_manifest.dart';
import 'package:pharmaguide/services/release_store.dart';

typedef RemoteReleaseProbe = Future<RemoteRelease?> Function();
typedef CatalogStager =
    Future<File> Function({
      required String version,
      String? storagePath,
      String? expectedSha256,
      CompressedCatalog? compressed,
    });
typedef RulesStager =
    Future<File> Function({
      required String version,
      required String storagePath,
      required String expectedSha256,
    });

/// What the phone holds now, as far as an update decision cares.
class InstalledRelease {
  const InstalledRelease({
    required this.sequence,
    required this.highestSequence,
    required this.catalogVersion,
    required this.rulesVersion,
    this.catalogSha256,
    this.rulesSha256,
    this.qualityWithheld = false,
    this.blocked = false,
    this.refused = const {},
  });

  factory InstalledRelease.of(ReleaseStore store) {
    final active = store.active;
    return InstalledRelease(
      sequence: active?.sequence ?? 0,
      highestSequence: store.highestSequence,
      catalogVersion: active?.catalogVersion,
      rulesVersion: active?.rulesVersion,
      catalogSha256: active?.catalogSha256,
      rulesSha256: active?.rulesSha256,
      qualityWithheld: active?.qualityWithheld ?? false,
      blocked: store.activeIsBlocked,
      refused: store.refused,
    );
  }

  final int sequence;
  final int highestSequence;
  final String? catalogVersion;
  final String? rulesVersion;
  final String? catalogSha256;
  final String? rulesSha256;
  final bool qualityWithheld;
  final bool blocked;

  /// Releases that failed to open on this phone.
  final Set<String> refused;
}

/// What someone who asked for an update check in Settings is told. Anything
/// short of a proven answer is [couldNotCheck], never [upToDate]. A check that
/// moved the phone off a blocked version is [deviceChanged], whatever else it
/// found, because the other lines would then be untrue.
enum UpdateCheckOutcome { upToDate, updateReady, couldNotCheck, deviceChanged }

/// Outcome of a [CatalogUpdaterService.checkForUpdate] call.
sealed class CatalogCheckResult {
  const CatalogCheckResult();
}

/// The probe could not reach the manifest endpoint, or the endpoint
/// returned no current row at all. The caller's installed release is
/// unaffected. Retry on the next refresh tick.
class CatalogUnreachable extends CatalogCheckResult {
  final Object? error;
  const CatalogUnreachable({this.error});
}

/// Nothing to take: the phone already holds this release or a newer one.
class CatalogUpToDate extends CatalogCheckResult {
  const CatalogUpToDate();
}

/// A release can't be trusted, or doesn't fit this phone (bad signature, an
/// unsigned row, a replay, a pair that isn't compatible). The last good pair
/// stays and the next tick checks again.
class CatalogRefused extends CatalogCheckResult {
  final String reason;
  const CatalogRefused({required this.reason});
}

/// A release this phone should take. [manifest] is null for an unsigned
/// catalog-only update.
class CatalogUpdateFound extends CatalogCheckResult {
  final ReleaseManifest? manifest;
  final String version;
  final String? checksum;
  const CatalogUpdateFound({
    required this.manifest,
    required this.version,
    this.checksum,
  });

  /// The active release names a version this release blocks, so waiting out
  /// the fleet jitter would keep it in use for no reason.
  bool isUrgentFor(InstalledRelease installed) =>
      installed.blocked ||
      (manifest?.blockedCatalog.contains(installed.catalogVersion) ?? false) ||
      (manifest?.blockedRules.contains(installed.rulesVersion) ?? false);
}

/// The download or validation failed. A partial file stays for Range-resume, and
/// nothing live changed.
class CatalogStageFailed extends CatalogCheckResult {
  final Object error;
  final String reason;
  const CatalogStageFailed({required this.error, required this.reason});
}

class CatalogStaged extends CatalogCheckResult {
  final ReleaseCandidate candidate;
  const CatalogStaged({required this.candidate});
}

class CatalogUpdaterService {
  final RemoteReleaseProbe probeRemoteRelease;
  final CatalogStager stageCatalog;
  final RulesStager stageRules;
  final Map<String, String> verificationKeys;
  final String? appVersion;

  CatalogUpdaterService({
    required this.probeRemoteRelease,
    required this.stageCatalog,
    required this.stageRules,
    Map<String, String>? verificationKeys,
    this.appVersion,
  }) : verificationKeys = verificationKeys ?? kReleaseVerificationKeys;

  /// Wires the production dependencies. Tests construct the service directly
  /// with fake callbacks instead.
  factory CatalogUpdaterService.production({
    required ReleaseStore store,
    SyncService? syncService,
  }) {
    final svc = syncService ?? SyncService();
    return CatalogUpdaterService(
      probeRemoteRelease: svc.fetchCurrentRelease,
      stageCatalog:
          ({
            required String version,
            String? storagePath,
            String? expectedSha256,
            CompressedCatalog? compressed,
          }) => svc.stageCatalog(
            downloads: store.downloads,
            version: version,
            storagePath: storagePath,
            expectedSha256: expectedSha256,
            compressed: compressed,
          ),
      stageRules:
          ({
            required String version,
            required String storagePath,
            required String expectedSha256,
          }) => svc.stageRules(
            downloads: store.downloads,
            version: version,
            storagePath: storagePath,
            expectedSha256: expectedSha256,
          ),
    );
  }

  /// Decides whether to take the current release. [onVerified] records what a
  /// verified manifest said before anything else can fail, so a revocation and
  /// the replay floor survive a refused or failed update.
  Future<CatalogCheckResult> checkForUpdate({
    required InstalledRelease installed,
    bool forceDownload = false,
    Future<void> Function(ReleaseManifest manifest)? onVerified,
  }) async {
    final RemoteRelease? remote;
    try {
      remote = await probeRemoteRelease();
    } on Object catch (e, st) {
      // Transient network failures (timeout, DNS, unreachable) are
      // expected on a scheduled probe — breadcrumb only, no Sentry
      // error event (PHARMAGUIDE-14). Real defects still report.
      if (CrashReportingService.isTransientNetworkError(e)) {
        CrashReportingService().log(
          'catalog_updater: manifest probe unreachable ($e)',
        );
      } else {
        CrashReportingService().recordError(
          e,
          st,
          hint: 'catalog_updater:unreachable',
        );
      }
      return CatalogUnreachable(error: e);
    }
    if (remote == null) return const CatalogUnreachable();

    return verificationKeys.isEmpty
        ? _checkUnsigned(remote, installed, forceDownload)
        : _checkSigned(remote, installed, onVerified);
  }

  CatalogCheckResult _checkUnsigned(
    RemoteRelease remote,
    InstalledRelease installed,
    bool forceDownload,
  ) {
    if (!forceDownload) {
      final remoteVersion = CatalogVersion.parse(remote.dbVersion);
      if (remoteVersion == null) {
        return CatalogUnreachable(
          error: FormatException(
            'Malformed remote catalog version',
            remote.dbVersion,
          ),
        );
      }
      final current = installed.catalogVersion;
      if (current != null && current.trim().isNotEmpty) {
        final currentVersion = CatalogVersion.parse(current);
        if (currentVersion == null) {
          return CatalogUnreachable(
            error: FormatException(
              'Malformed installed catalog version',
              current,
            ),
          );
        }
        if (remoteVersion.compareTo(currentVersion) <= 0) {
          return const CatalogUpToDate();
        }
      }
    }
    final id = ReleaseRecord.idFor(
      sequence: 0,
      catalogVersion: remote.dbVersion,
      rulesVersion: installed.rulesVersion ?? '',
    );
    if (installed.refused.contains(id)) {
      return _refuse('Catalog ${remote.dbVersion} failed to open here before');
    }
    return CatalogUpdateFound(
      manifest: null,
      version: remote.dbVersion,
      checksum: remote.checksum,
    );
  }

  Future<CatalogCheckResult> _checkSigned(
    RemoteRelease remote,
    InstalledRelease installed,
    Future<void> Function(ReleaseManifest manifest)? onVerified,
  ) async {
    final signed = remote.signedRelease;
    final signature = remote.releaseSignature;
    if (signed == null || signature == null) {
      return _refuse('Unsigned release ${remote.dbVersion}');
    }

    final ReleaseManifest manifest;
    try {
      manifest = await ReleaseManifest.verify(
        signedRelease: signed,
        signature: signature,
        keys: verificationKeys,
      );
    } on ReleaseManifestException catch (e) {
      return _refuse(e.message);
    }

    // A signature proves who published a release, not when: an older one
    // replayed by whoever controls storage must not move the phone backwards.
    if (manifest.sequence < installed.highestSequence) {
      return _refuse(
        'Release ${manifest.sequence} is older than '
        '${installed.highestSequence}',
      );
    }
    try {
      await onVerified?.call(manifest);
    } on Object catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        hint: 'catalog_updater:verified_manifest_not_persisted',
      );
      // The store keeps known revocations in memory. Return a normal result so
      // the bootstrap still settles them instead of abandoning the check.
      return _refuse('Verified release metadata could not be saved');
    }
    if (manifest.sequence <= installed.sequence) return const CatalogUpToDate();

    try {
      appVersion == null
          ? manifest.requireCompatible(
              currentRulesVersion: installed.rulesVersion,
            )
          : manifest.requireCompatible(
              currentRulesVersion: installed.rulesVersion,
              appVersion: appVersion!,
            );
    } on Exception catch (e) {
      return _refuse('Release ${manifest.sequence} is incompatible: $e');
    }
    // Decided here because downloading it again would only fail again.
    final id = ReleaseRecord.idFor(
      sequence: manifest.sequence,
      catalogVersion: manifest.catalog.version,
      rulesVersion: manifest.rules?.version ?? installed.rulesVersion ?? '',
    );
    if (installed.refused.contains(id)) {
      return _refuse('Release ${manifest.sequence} failed to open here before');
    }
    return CatalogUpdateFound(
      manifest: manifest,
      version: manifest.catalog.version,
    );
  }

  CatalogRefused _refuse(String reason) {
    CrashReportingService().log('catalog_updater: refused: $reason');
    return CatalogRefused(reason: reason);
  }

  /// Downloads what [found] needs. A file the phone already holds, proved by
  /// its published hash, isn't downloaded again, so a rules-only release costs
  /// only the rules.
  Future<CatalogCheckResult> stage(
    CatalogUpdateFound found, {
    required InstalledRelease installed,
  }) async {
    try {
      final manifest = found.manifest;
      if (manifest == null) {
        final staged = await stageCatalog(
          version: found.version,
          expectedSha256: found.checksum,
        );
        return CatalogStaged(
          candidate: ReleaseCandidate(
            sequence: 0,
            catalogVersion: found.version,
            catalogSha256: found.checksum,
            minRulesVersion: null,
            stagedCatalog: staged,
          ),
        );
      }

      final catalog = manifest.catalog;
      final reuseCatalog =
          catalog.sha256 == installed.catalogSha256 &&
          !installed.qualityWithheld;
      final stagedCatalog = reuseCatalog
          ? null
          : await stageCatalog(
              version: catalog.version,
              storagePath: catalog.path,
              expectedSha256: catalog.sha256,
              compressed: catalog.compressed,
            );

      final rules = manifest.rules;
      final reuseRules = rules == null || rules.sha256 == installed.rulesSha256;
      final stagedRules = reuseRules
          ? null
          : await stageRules(
              version: rules.version,
              storagePath: rules.path,
              expectedSha256: rules.sha256,
            );
      return CatalogStaged(
        candidate: ReleaseCandidate(
          sequence: manifest.sequence,
          catalogVersion: catalog.version,
          catalogSha256: catalog.sha256,
          minRulesVersion: manifest.minRulesVersion,
          stagedCatalog: stagedCatalog,
          stagedRules: stagedRules,
          rulesVersion: rules?.version,
          rulesSha256: rules?.sha256,
        ),
      );
    } on CatalogStorageFullException catch (e) {
      // Expected on a full phone, on every refresh. Not a defect to report.
      CrashReportingService().log('catalog_updater: $e');
      return CatalogStageFailed(error: e, reason: 'Staging failed: $e');
    } on Object catch (e, st) {
      CrashReportingService().recordError(
        e,
        st,
        hint: 'catalog_updater:stage_failed',
      );
      return CatalogStageFailed(error: e, reason: 'Staging failed: $e');
    }
  }
}
