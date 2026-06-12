import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/core/utils/app_version.dart';
import 'package:pharmaguide/core/utils/retry.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart'
    show PublicFetchDeniedException;
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/services/catalog_version.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

/// Thrown when a downloaded catalog passes integrity + version checks but
/// is refused activation because this app build cannot safely read it
/// (manifest `min_app_version` above us, or schema major unsupported).
class CatalogVersionGateException implements Exception {
  final String message;
  const CatalogVersionGateException(this.message);

  @override
  String toString() => 'CatalogVersionGateException: $message';
}

/// Handles OTA database updates from Supabase storage.
class SyncService {
  SyncService({
    Future<String?> Function()? currentDbVersionFetcher,
    String appVersion = kAppVersion,
    http.Client Function()? httpClientFactory,
    Future<void> Function()? onCatalogActivated,
  }) : _currentDbVersionFetcher = currentDbVersionFetcher,
       _appVersion = appVersion,
       _httpClientFactory = httpClientFactory ?? http.Client.new,
       _onCatalogActivated = onCatalogActivated;

  final Future<String?> Function()? _currentDbVersionFetcher;
  final String _appVersion;
  final http.Client Function() _httpClientFactory;

  /// Invoked after a staged catalog is successfully promoted to the live
  /// path. Used to invalidate caches keyed against the previous snapshot
  /// (e.g. `UserDatabase.clearDetailCache()` — cached detail blobs may not
  /// match the new rows' `detail_blob_sha256`). Failures are logged
  /// non-fatally; they never roll back an otherwise-successful activation.
  final Future<void> Function()? _onCatalogActivated;

  static const _manifestTimeout = Duration(seconds: 8);
  static const _downloadConnectTimeout = Duration(seconds: 10);

  /// Returns the current remote DB version published in export_manifest.
  Future<String?> fetchCurrentDbVersion() async {
    final injected = _currentDbVersionFetcher;
    if (injected != null) {
      return injected();
    }

    final manifest = await retryWithBackoff(
      () => supabase
          .from(SupabaseContract.manifestTable)
          .select('db_version')
          .eq('is_current', true)
          .limit(1)
          .maybeSingle(),
      timeout: _manifestTimeout,
    );

    return manifest?['db_version'] as String?;
  }

  /// Check if a new database version is available.
  /// Compares local export_manifest version against remote.
  Future<bool> isUpdateAvailable(String localVersion) async {
    try {
      final remoteVersion = await fetchCurrentDbVersion();
      return CatalogVersion.isRemoteNewer(
        remoteVersion: remoteVersion,
        localVersion: localVersion,
      );
    } on Object {
      return false;
    }
  }

  /// Get the path where the core database should live.
  Future<String> getCoreDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'pharmaguide_core.db');
  }

  /// Get the path where the user database should live.
  Future<String> getUserDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'user_data.db');
  }

  /// Download the core database from Supabase storage.
  /// Fetches the current version from export_manifest, then downloads
  /// from the `pharmaguide` bucket at `v{db_version}/pharmaguide_core.db`.
  Future<String> downloadCoreDb({String? expectedVersion}) async {
    final validatedVersion = await stageCoreDbDownload(
      expectedVersion: expectedVersion,
    );
    await activateStagedCoreDbIfPresent();
    return validatedVersion;
  }

  /// Downloads the latest database into staging and validates it.
  ///
  /// Cleanup contract (resume support):
  /// - Transient download failure → the partial `.staging` file is KEPT so
  ///   the next attempt can resume via HTTP Range.
  /// - Validation failure (corrupt / version mismatch / version gate) →
  ///   the staged file is deleted; it can never become valid.
  Future<String> stageCoreDbDownload({String? expectedVersion}) async {
    final dbPath = await getCoreDbPath();
    final stagingPath = '$dbPath.staging';
    final stagingFile = File(stagingPath);

    final dbVersion = expectedVersion ?? await fetchCurrentDbVersion();
    if (dbVersion == null) {
      throw Exception('No current export_manifest entry found');
    }

    final storagePath = SupabaseContract.coreDbPath(dbVersion);

    // A partial .staging left over from a DIFFERENT version must not be
    // resumed into — drop it and start fresh for this version.
    await _prepareStagingForVersion(stagingFile, dbVersion);

    // Download failures propagate WITHOUT deleting the staging file so a
    // later attempt can resume the partial download.
    await _downloadToStaging(storagePath, stagingFile);

    try {
      final validatedVersion = await _validateStagedDatabase(
        stagingPath,
        expectedVersion: dbVersion,
      );
      await _deleteStagingVersionMarker(stagingFile);
      return validatedVersion;
    } on Object {
      // The fully-downloaded file failed validation — it is permanently
      // unusable, so clean it up (best-effort: a cleanup failure must not
      // mask the validation error).
      try {
        if (await stagingFile.exists()) {
          await stagingFile.delete();
        }
      } on Object catch (cleanupError, st) {
        CrashReportingService().recordError(
          cleanupError,
          st,
          hint: 'catalog_sync:staging_cleanup_failed',
        );
      }
      await _deleteStagingVersionMarker(stagingFile);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // Download internals
  // ---------------------------------------------------------------------

  File _versionMarkerFor(File stagingFile) =>
      File('${stagingFile.path}.version');

  /// Sidecar bookkeeping so Range-resume never mixes bytes from two
  /// different catalog versions into one staging file.
  Future<void> _prepareStagingForVersion(
    File stagingFile,
    String version,
  ) async {
    final marker = _versionMarkerFor(stagingFile);
    try {
      String? existingVersion;
      if (await marker.exists()) {
        existingVersion = (await marker.readAsString()).trim();
      }
      if (existingVersion != version && await stagingFile.exists()) {
        await stagingFile.delete();
      }
      await marker.writeAsString(version, flush: true);
    } on Object {
      // Marker bookkeeping is best-effort. If it fails, fail safe by
      // dropping any partial so we can't resume into a mixed file.
      try {
        if (await stagingFile.exists()) {
          await stagingFile.delete();
        }
      } on Object {
        // Validation is the final backstop for a mixed/corrupt file.
      }
    }
  }

  Future<void> _deleteStagingVersionMarker(File stagingFile) async {
    try {
      final marker = _versionMarkerFor(stagingFile);
      if (await marker.exists()) {
        await marker.delete();
      }
    } on Object {
      // Best-effort.
    }
  }

  /// Streams the catalog to [stagingFile]: public CDN URL first (streamed,
  /// resumable via Range), falling back to the authed `.download()` path
  /// when the CDN denies the request (bucket prefix not yet public). The
  /// authed fallback buffers the whole file in memory — acceptable as a
  /// temporary fallback until the dashboard change lands.
  Future<void> _downloadToStaging(String storagePath, File stagingFile) async {
    try {
      await retryWithBackoff(
        () => _streamPublicDownload(storagePath, stagingFile),
        retryIf: (e) => e is! PublicFetchDeniedException,
      );
      return;
    } on PublicFetchDeniedException catch (e) {
      CrashReportingService().log(
        'catalog public CDN fetch denied (HTTP ${e.statusCode}) — '
        'falling back to authed download',
      );
    }

    final bytes = await retryWithBackoff(
      () => supabase.storage
          .from(SupabaseContract.storageBucket)
          .download(storagePath),
    );
    await stagingFile.writeAsBytes(bytes, flush: true);
  }

  /// One streamed download attempt against the public CDN URL.
  ///
  /// Resume: when a partial `.staging` exists we send a `Range` header.
  /// - 206 → append to the partial; validate the final size against the
  ///   `Content-Range` total.
  /// - 200 → server ignored the Range; restart from zero (truncate).
  /// - 400/401/403/404 → [PublicFetchDeniedException] (not retried here;
  ///   caller falls back to the authed path).
  Future<void> _streamPublicDownload(
    String storagePath,
    File stagingFile,
  ) async {
    final url = supabase.storage
        .from(SupabaseContract.storageBucket)
        .getPublicUrl(storagePath);
    final client = _httpClientFactory();
    try {
      var existing = 0;
      if (await stagingFile.exists()) {
        existing = await stagingFile.length();
      }

      final request = http.Request('GET', Uri.parse(url));
      if (existing > 0) {
        request.headers['range'] = 'bytes=$existing-';
      }

      final response = await client
          .send(request)
          .timeout(_downloadConnectTimeout);

      if (PublicFetchDeniedException.deniedStatuses.contains(
        response.statusCode,
      )) {
        throw PublicFetchDeniedException(response.statusCode);
      }

      final int? expectedTotal;
      final IOSink sink;
      if (response.statusCode == 206 && existing > 0) {
        expectedTotal = _parseContentRangeTotal(
          response.headers['content-range'],
        );
        sink = stagingFile.openWrite(mode: FileMode.append);
      } else if (response.statusCode == 200) {
        // Full body (server ignored Range, or no partial existed) —
        // restart from zero. openWrite() truncates.
        final contentLength = response.contentLength;
        expectedTotal = (contentLength != null && contentLength > 0)
            ? contentLength
            : null;
        sink = stagingFile.openWrite();
      } else {
        throw HttpException(
          'catalog download failed: HTTP ${response.statusCode}',
          uri: request.url,
        );
      }

      try {
        await sink.addStream(response.stream);
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (expectedTotal != null) {
        final actual = await stagingFile.length();
        if (actual != expectedTotal) {
          // Truncated mid-stream — keep the partial; the retry attempt
          // (or next refresh tick) resumes from where we stopped.
          throw HttpException(
            'catalog download incomplete: $actual of $expectedTotal bytes',
            uri: request.url,
          );
        }
      }
    } finally {
      client.close();
    }
  }

  /// Parses the total size out of a `Content-Range: bytes 100-999/1000`
  /// header. Returns null when absent/unparseable (size check skipped —
  /// the integrity_check validation gate is the backstop).
  int? _parseContentRangeTotal(String? contentRange) {
    if (contentRange == null) return null;
    final slash = contentRange.lastIndexOf('/');
    if (slash < 0) return null;
    final totalStr = contentRange.substring(slash + 1).trim();
    if (totalStr == '*') return null;
    return int.tryParse(totalStr);
  }

  // ---------------------------------------------------------------------
  // Activation
  // ---------------------------------------------------------------------

  /// Promotes a validated staging database into the live path.
  /// Safe to call repeatedly; it no-ops if no staged file exists.
  Future<void> activateStagedCoreDbIfPresent() async {
    final dbPath = await getCoreDbPath();
    final stagingPath = '$dbPath.staging';
    final backupPath = '$dbPath.backup';
    final stagingFile = File(stagingPath);
    if (!await stagingFile.exists()) {
      return;
    }

    final currentFile = File(dbPath);
    final backupFile = File(backupPath);
    var backedUpCurrent = false;
    var activated = false;

    try {
      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      if (await currentFile.exists()) {
        await currentFile.rename(backupPath);
        backedUpCurrent = true;
      }

      await stagingFile.rename(dbPath);
      activated = true;

      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (_) {
      if (backedUpCurrent && await backupFile.exists()) {
        if (await currentFile.exists()) {
          await currentFile.delete();
        }
        await backupFile.rename(dbPath);
      }
      rethrow;
    } finally {
      // Cleanup is best-effort: a delete failure here must never mask the
      // original activation error (same pattern as catalog_swap.dart).
      try {
        if (await stagingFile.exists()) {
          await stagingFile.delete();
        }
      } on Object catch (e, st) {
        CrashReportingService().recordError(
          e,
          st,
          hint: 'catalog_sync:activation_cleanup_failed',
        );
      }
      await _deleteStagingVersionMarker(stagingFile);
    }

    if (activated) {
      // Cache invalidation: cached detail blobs were fetched against the
      // previous catalog snapshot. Never let a cache-clear failure undo a
      // successful activation — log and continue.
      final callback = _onCatalogActivated;
      if (callback != null) {
        try {
          await callback();
        } on Object catch (e, st) {
          CrashReportingService().recordError(
            e,
            st,
            hint: 'catalog_sync:detail_cache_clear_failed',
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------

  /// Test seam for [_validateStagedDatabase] (integrity check + version
  /// match + version gate) without going through a network download.
  @visibleForTesting
  Future<String> validateStagedDatabaseForTest(
    String dbPath, {
    required String expectedVersion,
  }) {
    return _validateStagedDatabase(dbPath, expectedVersion: expectedVersion);
  }

  /// Pure version-gate decision, extracted for unit testing.
  ///
  /// Fail-open ONLY when a key is entirely absent (older catalogs predate
  /// the keys). A key that is present but unparseable fails CLOSED — a
  /// catalog declaring compatibility requirements we cannot read must not
  /// be activated.
  @visibleForTesting
  static void enforceCatalogVersionGate({
    required String? minAppVersion,
    required String? schemaVersion,
    required String appVersion,
    int maxSupportedSchemaMajor = kMaxSupportedCatalogSchemaMajor,
  }) {
    if (minAppVersion != null && minAppVersion.trim().isNotEmpty) {
      final cmp = compareSemver(minAppVersion, appVersion);
      if (cmp == null) {
        throw CatalogVersionGateException(
          'Catalog min_app_version "$minAppVersion" is unparseable — '
          'refusing activation (fail closed).',
        );
      }
      if (cmp > 0) {
        throw CatalogVersionGateException(
          'Catalog requires app >= $minAppVersion but this build is '
          '$appVersion — refusing activation. Update the app to receive '
          'this catalog.',
        );
      }
    }

    if (schemaVersion != null && schemaVersion.trim().isNotEmpty) {
      final major = int.tryParse(schemaVersion.trim().split('.').first);
      if (major == null) {
        throw CatalogVersionGateException(
          'Catalog schema_version "$schemaVersion" is unparseable — '
          'refusing activation (fail closed).',
        );
      }
      if (major > maxSupportedSchemaMajor) {
        throw CatalogVersionGateException(
          'Catalog schema_version $schemaVersion exceeds the highest '
          'major this build supports ($maxSupportedSchemaMajor.x) — '
          'refusing activation.',
        );
      }
    }
  }

  /// Validates that a freshly-downloaded staging DB matches the version we
  /// thought we were downloading, and that this app build is allowed to
  /// read it.
  ///
  /// [expectedVersion] is the `db_version` build timestamp (e.g.
  /// `"2026.04.10.222555"`) pulled from the remote `export_manifest` table.
  /// [CoreDatabase.validateCatalogSnapshot] reads the same `db_version`
  /// field from the DB's embedded `export_manifest` key-value table, so the
  /// two values must match byte-for-byte. A mismatch means Supabase Storage
  /// served us a file that disagrees with its own manifest row — we refuse
  /// to activate it.
  ///
  /// VERSION GATE: after the version match, the embedded manifest's
  /// `min_app_version` and `schema_version` are checked against this app
  /// build (see [enforceCatalogVersionGate]). Refusals are logged to
  /// Sentry non-fatally and thrown as [CatalogVersionGateException], which
  /// deletes the staged file upstream.
  Future<String> _validateStagedDatabase(
    String dbPath, {
    required String expectedVersion,
  }) async {
    final db = CoreDatabase.open(dbPath);
    try {
      // T0.6: SQLite-level integrity check guards against corrupted
      // bytes that would still pass the version check (torn pages,
      // broken indexes, truncated payloads). PRAGMA integrity_check
      // returns a single row with the literal `'ok'` on success or one
      // or more rows describing the corruption.
      final integrityRows = await db
          .customSelect('PRAGMA integrity_check')
          .get();
      if (integrityRows.isEmpty) {
        throw StateError('PRAGMA integrity_check returned no rows');
      }
      final integrityResult = integrityRows.first.data.values.first?.toString();
      if (integrityResult != 'ok') {
        throw StateError(
          'Catalog integrity_check failed: ${integrityResult ?? "(null)"}',
        );
      }

      final validatedVersion = await db.validateCatalogSnapshot();
      if (validatedVersion != expectedVersion) {
        throw StateError(
          'Downloaded catalog version mismatch: '
          'expected db_version $expectedVersion, got $validatedVersion. '
          'The remote Storage file disagrees with the remote manifest row.',
        );
      }

      // Version gate — mirrors how the interaction DB embeds
      // min_app_version/schema_version in its metadata table
      // (interaction_database.dart getMetadata()). Keys missing entirely
      // (older catalogs) fail open; present-but-incompatible fails closed.
      final minAppVersion = await _readManifestValueSafe(db, 'min_app_version');
      final schemaVersion = await _readManifestValueSafe(db, 'schema_version');
      try {
        enforceCatalogVersionGate(
          minAppVersion: minAppVersion,
          schemaVersion: schemaVersion,
          appVersion: _appVersion,
        );
      } on CatalogVersionGateException catch (e, st) {
        CrashReportingService().recordError(
          e,
          st,
          fatal: false,
          hint: 'catalog_sync:version_gate_refused',
        );
        rethrow;
      }

      return validatedVersion;
    } finally {
      await db.close();
    }
  }

  /// Reads a manifest key, treating a missing table/row as null (older
  /// catalogs predate the embedded export_manifest table).
  Future<String?> _readManifestValueSafe(CoreDatabase db, String key) async {
    try {
      return await db.readManifestValue(key);
    } on Object {
      return null;
    }
  }
}
