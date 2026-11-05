import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pharmaguide/core/utils/app_version.dart';
import 'package:pharmaguide/core/utils/retry.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart'
    show enforceInteractionDatabaseVersionGate;
import 'package:pharmaguide/data/supabase/detail_blob_service.dart'
    show PublicFetchDeniedException;
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/release_store.dart'
    show availableDiskBytes;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, StorageException;

/// Thrown when a downloaded catalog passes integrity + version checks but
/// is refused activation because this app build cannot safely read it
/// (manifest `min_app_version` above us, or schema major unsupported).
class CatalogVersionGateException implements Exception {
  final String message;
  const CatalogVersionGateException(this.message);

  @override
  String toString() => 'CatalogVersionGateException: $message';
}

/// The current `export_manifest` row. Signed fields are absent on rows published
/// before release signing, and before their migration has been applied.
class RemoteRelease {
  const RemoteRelease({
    required this.dbVersion,
    this.checksum,
    this.signedRelease,
    this.releaseSignature,
  });

  final String dbVersion;
  final String? checksum;
  final String? signedRelease;
  final String? releaseSignature;
}

/// Room an update needs beyond its download and the decompressed catalog. It
/// covers the copy of the rules that goes into the new release (25.1 MB in the
/// October 2026 catalog) and SQLite's working space. The active and previous
/// releases are already on disk and stay there until the next launch, so the
/// free space measured is what is left with both of them kept.
const int kCatalogHeadroomBytes = 64 << 20;

/// There isn't room to take this update. Nothing was written, and the next
/// refresh checks again. It carries no numbers because errors reach crash
/// reporting, and Apple's required-reason rule for reading disk space
/// (`ios/Runner/PrivacyInfo.xcprivacy`) keeps that reading on the device.
class CatalogStorageFullException implements Exception {
  const CatalogStorageFullException();

  @override
  String toString() => 'CatalogStorageFullException';
}

/// A compressed catalog that can't become the catalog it names.
class CompressedCatalogRejected implements Exception {
  const CompressedCatalogRejected(this.message);

  final String message;

  @override
  String toString() => 'CompressedCatalogRejected: $message';
}

/// The gzip of a catalog. It only changes how the bytes arrive: what activates
/// must still hash to the catalog's own checksum, signed or from the manifest row.
@immutable
class CompressedCatalog {
  const CompressedCatalog({
    required this.path,
    required this.sha256,
    required this.size,
    required this.decompressedSize,
  });

  final String path;
  final String sha256;
  final int size;
  final int decompressedSize;

  /// Null unless [raw] is complete and names [expectedPath]. A catalog without a
  /// usable compressed form still arrives through its plain file.
  static CompressedCatalog? tryParse(
    Object? raw, {
    required String expectedPath,
  }) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final sha256 = raw['sha256'];
    final size = raw['size'];
    final decompressedSize = raw['decompressed_size'];
    if (path != expectedPath ||
        sha256 is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
        size is! int ||
        size <= 0 ||
        decompressedSize is! int ||
        decompressedSize <= 0) {
      return null;
    }
    return CompressedCatalog(
      path: expectedPath,
      sha256: sha256,
      size: size,
      decompressedSize: decompressedSize,
    );
  }
}

/// A file with the wrong hash has been deleted by the time this is thrown.
class _ArtifactHashMismatch extends StateError {
  _ArtifactHashMismatch(super.message);
}

/// Handles OTA database updates from Supabase storage.
class SyncService {
  SyncService({
    this._appVersion = kAppVersion,
    http.Client Function()? httpClientFactory,
    Future<int?> Function(String path)? availableBytes,
  }) : _httpClientFactory = httpClientFactory ?? http.Client.new,
       _availableBytes = availableBytes ?? availableDiskBytes;

  final String _appVersion;
  final http.Client Function() _httpClientFactory;
  final Future<int?> Function(String path) _availableBytes;

  static const _manifestTimeout = Duration(seconds: 8);
  static const _downloadConnectTimeout = Duration(seconds: 10);

  /// Rolling per-chunk watchdog for the download BODY stream: if no bytes
  /// arrive for this long the stream fails with [TimeoutException] instead
  /// of hanging forever. Generous enough for a slow cellular link (any
  /// forward progress resets it), short enough that a dead connection
  /// frees the OTA subsystem within the session.
  static const _downloadInactivityTimeout = Duration(seconds: 30);

  /// Overall deadline for the authed `.download()` fallback. That path
  /// buffers the whole file via a single `Future<Uint8List>` — there is no
  /// per-chunk signal to run an inactivity watchdog against, so a stalled
  /// connection would hang this await forever and wedge the OTA subsystem
  /// (including the manual retry button) for the session, exactly like the
  /// body-stream hang the watchdog fixed. A total deadline is the only tool
  /// the buffered API offers; it errs generous (large catalog on a slow link)
  /// and a timeout surfaces as a retryable [TimeoutException] under
  /// retryWithBackoff.
  static const _authedDownloadTimeout = Duration(minutes: 2);

  /// Keeps the app updating on a database that doesn't have the signed columns
  /// yet: PostgREST answers 42703 for a named column the table lacks. Reads a
  /// list because `maybeSingle` reports every failure as code 400, hiding that.
  Future<Map<String, dynamic>?> _readCurrentManifestRow() async {
    List<Map<String, dynamic>> rows;
    try {
      rows = await supabase
          .from(SupabaseContract.manifestTable)
          .select('db_version,checksum,signed_release,release_signature')
          .eq('is_current', true)
          .limit(1);
    } on PostgrestException catch (error) {
      if (error.code != '42703') rethrow;
      rows = await supabase
          .from(SupabaseContract.manifestTable)
          .select('db_version,checksum')
          .eq('is_current', true)
          .limit(1);
    }
    return rows.firstOrNull;
  }

  /// Returns the current `export_manifest` row.
  Future<RemoteRelease?> fetchCurrentRelease() async {
    final span = _startCatalogSpan(
      operation: 'http.client',
      description: 'Fetch current catalog manifest',
      surface: 'catalog_manifest',
    );
    SpanStatus status = const SpanStatus.ok();
    try {
      final row = await retryWithBackoff(
        _readCurrentManifestRow,
        timeout: _manifestTimeout,
      );
      final version = row?['db_version'] as String?;
      span
        ?..setData('catalog.has_current', version != null)
        ..setData('catalog.version', version);
      if (row == null || version == null) return null;
      return RemoteRelease(
        dbVersion: version,
        checksum: row['checksum'] as String?,
        signedRelease: row['signed_release'] as String?,
        releaseSignature: row['release_signature'] as String?,
      );
    } on Object catch (error) {
      status = _catalogSpanStatusForError(error);
      span?.throwable = error;
      rethrow;
    } finally {
      await _finishCatalogSpan(span, status);
    }
  }

  /// Downloads a catalog into [downloads] and validates it, without touching
  /// anything live. [expectedSha256], when known, is checked on the bytes as
  /// published, before anything opens the file.
  ///
  /// With a checksum to prove the result against, it takes the compressed form:
  /// [compressed] from a signed release, or else the published descriptor. The
  /// plain file remains for catalogs without one, and for a compressed file that
  /// can't produce this catalog.
  ///
  /// Cleanup contract (resume support):
  /// - Transient download failure → the partial file is KEPT so the next
  ///   attempt can resume via HTTP Range.
  /// - Hash or validation failure (corrupt / version mismatch / version gate)
  ///   → the file is deleted; it can never become valid.
  Future<File> stageCatalog({
    required Directory downloads,
    required String version,
    String? storagePath,
    String? expectedSha256,
    CompressedCatalog? compressed,
  }) async {
    final stagingFile = File(p.join(downloads.path, 'catalog.staging'));
    final span = _startCatalogSpan(
      operation: 'app.catalog',
      description: 'Stage catalog DB download',
      surface: 'catalog_stage',
    );
    span?.setData('catalog.expected_version', version);
    SpanStatus status = const SpanStatus.ok();
    try {
      await downloads.create(recursive: true);
      final source = expectedSha256 == null
          ? null
          : compressed ??
                await _readCompressedDescriptor(version, expectedSha256);
      final delivered =
          source != null &&
          await _stageFromCompressed(
            source,
            stagingFile: stagingFile,
            version: version,
            expectedSha256: expectedSha256!,
          );
      span?.setData('catalog.compressed', delivered);
      if (!delivered) {
        if (source != null) {
          await _requireRoom(
            stagingFile.parent.path,
            source.decompressedSize + kCatalogHeadroomBytes,
          );
        }
        await _downloadVerified(
          storagePath: storagePath ?? SupabaseContract.coreDbPath(version),
          stagingFile: stagingFile,
          version: version,
          expectedSha256: expectedSha256,
        );
      }
      try {
        final validatedVersion = await _validateStagedDatabase(
          stagingFile.path,
          expectedVersion: version,
        );
        span?.setData('catalog.validated_version', validatedVersion);
        await _deleteStagingVersionMarker(stagingFile);
        return stagingFile;
      } on Object {
        await _deleteQuietly(stagingFile);
        await _deleteStagingVersionMarker(stagingFile);
        rethrow;
      }
    } on Object catch (error) {
      status = _catalogSpanStatusForError(error, fallback: status);
      span?.throwable = error;
      rethrow;
    } finally {
      await _finishCatalogSpan(span, status);
    }
  }

  /// Downloads a rules file into [downloads] and checks it the same way. The
  /// pair check has already passed; this proves the file is what was named.
  Future<File> stageRules({
    required Directory downloads,
    required String version,
    required String storagePath,
    required String expectedSha256,
  }) async {
    final stagingFile = File(p.join(downloads.path, 'rules.staging'));
    await _downloadVerified(
      storagePath: storagePath,
      stagingFile: stagingFile,
      version: version,
      expectedSha256: expectedSha256,
    );
    final db = InteractionDatabase.open(stagingFile.path);
    var valid = false;
    try {
      final integrity = await db.customSelect('PRAGMA integrity_check').get();
      if (integrity.isEmpty || integrity.first.data.values.first != 'ok') {
        throw StateError('Rules integrity_check failed');
      }
      final metadata = await db.getMetadata();
      if (metadata.interactionDbVersion != version) {
        throw StateError(
          'Downloaded rules are ${metadata.interactionDbVersion}, '
          'expected $version',
        );
      }
      enforceInteractionDatabaseVersionGate(
        minAppVersion: metadata.minAppVersion,
        schemaVersion: metadata.schemaVersion,
        appVersion: _appVersion,
      );
      valid = true;
      return stagingFile;
    } finally {
      await db.close();
      if (!valid) await _deleteQuietly(stagingFile);
      await _deleteStagingVersionMarker(stagingFile);
    }
  }

  /// Null when there's no usable descriptor, including catalogs published
  /// before compression. Transient lookup failures propagate for a later retry.
  /// It can't change what activates: it must name this catalog's checksum, and
  /// the result must then hash to it.
  Future<CompressedCatalog?> _readCompressedDescriptor(
    String version,
    String expectedSha256,
  ) async {
    final client = _httpClientFactory();
    try {
      final url = supabase.storage
          .from(SupabaseContract.storageBucket)
          .getPublicUrl(
            SupabaseContract.compressedCoreDbDescriptorPath(version),
          );
      final response = await client
          .get(Uri.parse(url))
          .timeout(_manifestTimeout);
      if (response.statusCode != 200) {
        final error = StorageException(
          response.body,
          statusCode: response.statusCode.toString(),
        );
        // Public auth denial is not a missing artifact, but the established
        // plain path can still deliver it through authenticated Storage access.
        if (response.statusCode == 401 ||
            response.statusCode == 403 ||
            _isMissingStorageObject(error)) {
          return null;
        }
        throw error;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map ||
          decoded['version'] != version ||
          decoded['decompressed_sha256'] != _hexSha256(expectedSha256)) {
        return null;
      }
      return CompressedCatalog.tryParse(
        decoded,
        expectedPath: SupabaseContract.compressedCoreDbPath(version),
      );
    } on FormatException catch (error) {
      CrashReportingService().log(
        'catalog descriptor invalid: ${error.runtimeType}',
      );
      return null;
    } finally {
      client.close();
    }
  }

  /// Fills [stagingFile] from the compressed form. False means that form can't
  /// deliver this catalog and the plain file should be tried. Anything about
  /// this moment, such as the network or the disk, throws, so the next attempt
  /// resumes with the same small file.
  Future<bool> _stageFromCompressed(
    CompressedCatalog compressed, {
    required File stagingFile,
    required String version,
    required String expectedSha256,
  }) async {
    final gz = File('${stagingFile.parent.path}/catalog.gz.staging');
    // The decompression scratch file is disposable. Keep plain download bytes
    // and their version marker until the verified gzip atomically replaces them;
    // a missing/rejected gzip must not erase the plain fallback's Range resume.
    await _deleteQuietly(File('${stagingFile.path}.decompressing'));
    // Free an unusable older plain partial before measuring room. Fresh attempts
    // create no marker here; matching-version bytes remain available for resume.
    if (await stagingFile.exists()) {
      await _prepareStagingForVersion(stagingFile, version);
    }

    await _requireRoom(
      stagingFile.parent.path,
      compressed.size -
          await _resumableBytes(gz, version, compressed.size) +
          compressed.decompressedSize +
          kCatalogHeadroomBytes,
    );

    Future<void> discard() async {
      await _deleteQuietly(gz);
      await _deleteStagingVersionMarker(gz);
    }

    try {
      await _downloadVerified(
        storagePath: compressed.path,
        stagingFile: gz,
        version: version,
        expectedSha256: compressed.sha256,
        knownSize: compressed.size,
      );
      await decompressCatalogOffUiIsolate(
        source: gz.path,
        target: stagingFile.path,
        expectedSha256: _hexSha256(expectedSha256),
        expectedBytes: compressed.decompressedSize,
      );
    } on _ArtifactHashMismatch catch (error) {
      CrashReportingService().log('catalog gz refused: $error');
      return false;
    } on CompressedCatalogRejected catch (error) {
      CrashReportingService().log('catalog gz refused: $error');
      await discard();
      return false;
    } on StorageException catch (error) {
      // A failed storage service is not proof the compressed object is absent.
      // Preserve partial bytes and let the normal updater retry those failures.
      if (!_isMissingStorageObject(error)) rethrow;
      CrashReportingService().log('catalog gz missing: ${error.statusCode}');
      await discard();
      return false;
    }
    await discard();
    return true;
  }

  /// Storage's two definitive absence responses, shared by descriptor and gzip.
  /// Anything else is retryable uncertainty, never evidence to spend a fallback.
  bool _isMissingStorageObject(StorageException error) {
    var code = error.error;
    if (error.statusCode == '400' && code == null) {
      // The pinned storage SDK leaves download error JSON in message.
      try {
        final payload = jsonDecode(error.message);
        if (payload is Map && payload['error'] is String) {
          code = payload['error'] as String;
        }
      } on FormatException {
        // An unrecognized response is not evidence of a missing object.
      }
    }
    return error.statusCode == '404' ||
        (error.statusCode == '400' && code == 'not_found');
  }

  /// What an interrupted download of [file] for this [version] already holds.
  Future<int> _resumableBytes(File file, String version, int size) async {
    final marker = _versionMarkerFor(file);
    if (!await file.exists() || !await marker.exists()) return 0;
    if ((await marker.readAsString()).trim() != version) return 0;
    final length = await file.length();
    return length <= size ? length : 0;
  }

  Future<void> _requireRoom(String directory, int neededBytes) async {
    final free = await _availableBytes(directory);
    if (free != null && free < neededBytes) {
      throw const CatalogStorageFullException();
    }
  }

  Future<void> _downloadVerified({
    required String storagePath,
    required File stagingFile,
    required String version,
    required String? expectedSha256,
    int? knownSize,
  }) async {
    await stagingFile.parent.create(recursive: true);
    // A partial left over from a DIFFERENT version must not be resumed into —
    // drop it and start fresh for this version.
    await _prepareStagingForVersion(stagingFile, version);
    final existing = await stagingFile.exists()
        ? await stagingFile.length()
        : 0;
    if (knownSize != null && existing > knownSize) await stagingFile.delete();
    // A file that is already whole, from a kill before it was used, needs no
    // network. Download failures propagate WITHOUT deleting the file so a later
    // attempt can resume the partial download.
    if (existing != knownSize) {
      await _downloadToStaging(storagePath, stagingFile);
    }
    if (expectedSha256 == null) return;
    final actual = await _sha256OffUiIsolate(stagingFile.path);
    if (actual != _hexSha256(expectedSha256)) {
      await _deleteQuietly(stagingFile);
      await _deleteStagingVersionMarker(stagingFile);
      throw _ArtifactHashMismatch(
        'Downloaded file for $version failed its hash check',
      );
    }
  }

  String _hexSha256(String value) =>
      (value.startsWith('sha256:') ? value.substring(7) : value).toLowerCase();

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object catch (cleanupError, st) {
      // A cleanup failure must not mask the error that got us here.
      CrashReportingService().recordError(
        cleanupError,
        st,
        hint: 'catalog_sync:staging_cleanup_failed',
      );
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

    final bytes = await retryWithBackoff(() async {
      final span = _startCatalogSpan(
        operation: 'http.client',
        description: 'GET Supabase catalog fallback',
        surface: 'catalog_download_authed',
      );
      SpanStatus status = const SpanStatus.ok();
      try {
        final downloaded = await supabase.storage
            .from(SupabaseContract.storageBucket)
            .download(storagePath)
            .timeout(_authedDownloadTimeout);
        span?.setData('http.response.body.size', downloaded.length);
        return downloaded;
      } on Object catch (error) {
        status = _catalogSpanStatusForError(error);
        span?.throwable = error;
        rethrow;
      } finally {
        await _finishCatalogSpan(span, status);
      }
    });
    await stagingFile.writeAsBytes(bytes, flush: true);
  }

  /// One streamed download attempt against the public CDN URL.
  ///
  /// Resume: when a partial `.staging` exists we send a `Range` header.
  /// - 206 → append to the partial; validate the final size against the
  ///   `Content-Range` total.
  /// - 200 → server ignored the Range; restart from zero (truncate).
  /// - 416 → the partial reaches or passes the end of the object.
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
    final span = _startCatalogSpan(
      operation: 'http.client',
      description: 'GET Supabase catalog public',
      surface: 'catalog_download_public',
    );
    SpanStatus status = const SpanStatus.ok();
    try {
      var existing = 0;
      if (await stagingFile.exists()) {
        existing = await stagingFile.length();
      }
      span
        ?..setData('download.resume_from_bytes', existing)
        ..setData('http.request.method', 'GET');

      final request = http.Request('GET', Uri.parse(url));
      if (existing > 0) {
        request.headers['range'] = 'bytes=$existing-';
      }

      final response = await client
          .send(request)
          .timeout(_downloadConnectTimeout);
      status = SpanStatus.fromHttpStatusCode(response.statusCode);
      span
        ?..setData('http.response.status_code', response.statusCode)
        ..setData('http.response.body.size', response.contentLength);

      if (PublicFetchDeniedException.deniedStatuses.contains(
        response.statusCode,
      )) {
        throw PublicFetchDeniedException(response.statusCode);
      }

      if (response.statusCode == 416 && existing > 0) {
        // Nothing lies past where this file ends. A whole file, left by a kill
        // just before its hash check, goes on to that check. Anything else can
        // never resume, so the retry starts over.
        final total = _parseContentRangeTotal(
          response.headers['content-range'],
        );
        if (total == existing) return;
        await stagingFile.delete();
        throw HttpException(
          'catalog partial does not fit the object: $existing of $total bytes',
          uri: request.url,
        );
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
        // The connect timeout above only covers the response HEADERS; the
        // body can stall indefinitely on a dead connection, which would
        // hang this await — and with it the whole OTA subsystem for the
        // session (the caller's `_syncInFlight` guard is only cleared when
        // this returns, freezing even the manual retry button). The
        // watchdog turns a stalled body into a retryable TimeoutException;
        // the partial `.staging` file is kept for Range-resume.
        await sink.addStream(
          inactivityWatchdogStream(
            response.stream,
            inactivity: _downloadInactivityTimeout,
          ),
        );
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (expectedTotal != null) {
        final actual = await stagingFile.length();
        span
          ?..setData('download.expected_total_bytes', expectedTotal)
          ..setData('download.actual_total_bytes', actual);
        if (actual != expectedTotal) {
          // Truncated mid-stream — keep the partial; the retry attempt
          // (or next refresh tick) resumes from where we stopped.
          throw HttpException(
            'catalog download incomplete: $actual of $expectedTotal bytes',
            uri: request.url,
          );
        }
      }
    } on Object catch (error) {
      status = _catalogSpanStatusForError(error, fallback: status);
      span?.throwable = error;
      rethrow;
    } finally {
      await _finishCatalogSpan(span, status);
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

  /// Pure version-gate decision.
  ///
  /// Fails CLOSED on every uncertainty: a missing, blank or unparseable key,
  /// a catalog that needs a newer app, a schema major this build cannot
  /// read, or a schema older than [kMinSupportedCatalogSchema]. A refused
  /// catalog is not activated; the current catalog stays in place.
  static void enforceCatalogVersionGate({
    required String? minAppVersion,
    required String? schemaVersion,
    required String appVersion,
    int maxSupportedSchemaMajor = kMaxSupportedCatalogSchemaMajor,
  }) {
    if (minAppVersion == null || minAppVersion.trim().isEmpty) {
      throw const CatalogVersionGateException(
        'Catalog has no min_app_version — refusing activation (fail closed).',
      );
    }
    if (schemaVersion == null || schemaVersion.trim().isEmpty) {
      throw const CatalogVersionGateException(
        'Catalog has no schema_version — refusing activation (fail closed).',
      );
    }

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
    final belowMinimum = compareSemver(
      schemaVersion,
      kMinSupportedCatalogSchema,
    );
    if (belowMinimum == null || belowMinimum < 0) {
      throw CatalogVersionGateException(
        'Catalog schema_version $schemaVersion is older than '
        '$kMinSupportedCatalogSchema, which has no product safety status — '
        'refusing activation.',
      );
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

      // Structural schema guard: schema_version only gates the MAJOR, and a
      // partial/broken build (or intra-major drift that dropped/renamed a
      // column) can still declare a compatible schema_version. Refuse a
      // catalog missing any column the reader cannot function without —
      // fail closed and keep the current catalog rather than silently
      // misread a structurally-incompatible one.
      await _assertStagedSchemaColumns(db);

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

  /// Load-bearing columns that must exist in every staged catalog and are
  /// NOT covered by `CoreDatabase._ensureCompatColumns` backfill — so their
  /// absence signals a broken or wrong-schema build, not merely an old
  /// snapshot. `mapped_coverage` gates the "never show safe below 0.3
  /// coverage" safety rule. The v4 score columns are deliberately excluded:
  /// they ARE in the compat backfill (a snapshot missing them degrades to
  /// unscored, which the app handles), and — because that backfill runs on
  /// open before this check — verifying them here would be masked anyway.
  static const Set<String> _requiredCoreColumns = {
    'dsld_id',
    'product_name',
    'export_version',
    'mapped_coverage',
  };

  /// Fail closed if the staged catalog's `products_core` is missing any
  /// [_requiredCoreColumns]. `schema_version` only gates the major; this
  /// catches a partial/broken/intra-major-drifted build that still declares
  /// a compatible `schema_version` and would otherwise activate and silently
  /// misread. Reported to Sentry so the drift is visible.
  Future<void> _assertStagedSchemaColumns(CoreDatabase db) async {
    final rows = await db
        .customSelect("PRAGMA table_info('products_core')")
        .get();
    final present = rows
        .map((r) => r.data['name']?.toString())
        .whereType<String>()
        .toSet();
    final missing = _requiredCoreColumns.difference(present);
    if (missing.isEmpty) return;

    final error = CatalogVersionGateException(
      'Catalog products_core is missing required column(s): '
      '${(missing.toList()..sort()).join(", ")} — refusing activation '
      '(fail closed).',
    );
    CrashReportingService().recordError(
      error,
      StackTrace.current,
      fatal: false,
      hint: 'catalog_sync:schema_columns_missing',
    );
    throw error;
  }
}

Future<String> _sha256OffUiIsolate(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
  debugName: 'catalog-hash',
);

/// Runs [decompressCatalogFile] on its own isolate and returns that isolate's
/// name. A catalog is tens of megabytes, and scrolling continues while it unpacks.
@visibleForTesting
Future<String?> decompressCatalogOffUiIsolate({
  required String source,
  required String target,
  required String expectedSha256,
  required int expectedBytes,
}) => Isolate.run(() async {
  await decompressCatalogFile(
    source: source,
    target: target,
    expectedSha256: expectedSha256,
    expectedBytes: expectedBytes,
  );
  return Isolate.current.debugName;
}, debugName: 'catalog-decompress');

/// Streams the gzip at [source] to [target], which appears only once it holds
/// exactly the expected bytes. Until then the work is in `.decompressing`, which
/// a kill can leave behind and nothing ever reads. Output stops at [expectedBytes],
/// so a file can't expand past the room that was checked for it.
///
/// Throws [CompressedCatalogRejected] for a file that can't become this catalog,
/// and [FileSystemException] when the disk fails or fills.
@visibleForTesting
Future<void> decompressCatalogFile({
  required String source,
  required String target,
  required String expectedSha256,
  required int expectedBytes,
}) async {
  final partial = File('$target.decompressing');
  final digest = _DigestSink();
  final hasher = sha256.startChunkedConversion(digest);
  var finished = false;
  try {
    final output = await partial.open(mode: FileMode.write);
    try {
      var written = 0;
      await for (final chunk in File(
        source,
      ).openRead().transform(gzip.decoder)) {
        written += chunk.length;
        if (written > expectedBytes) {
          throw const CompressedCatalogRejected(
            'expands past its declared size',
          );
        }
        hasher.add(chunk);
        await output.writeFrom(chunk);
      }
      if (written != expectedBytes) {
        throw CompressedCatalogRejected(
          'holds $written bytes, expected $expectedBytes',
        );
      }
      await output.flush();
    } on FormatException catch (error) {
      throw CompressedCatalogRejected('is not valid gzip: ${error.message}');
    } finally {
      await output.close();
    }
    hasher.close();
    if (digest.value.toString() != expectedSha256) {
      throw const CompressedCatalogRejected('failed its hash check');
    }
    await partial.rename(target);
    finished = true;
  } finally {
    if (!finished) {
      try {
        if (await partial.exists()) await partial.delete();
      } on Object {
        // Cleared before the next attempt; the error that got us here matters more.
      }
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Wraps a download byte [source] with a rolling inactivity watchdog: any
/// gap between chunks longer than [inactivity] errors the stream with a
/// [TimeoutException] and then CLOSES it, so a consumer like
/// `IOSink.addStream` (which only completes on done/error) can never hang
/// on a stalled connection. Chunks that keep flowing reset the window, so
/// slow-but-progressing downloads are never aborted.
///
/// The [TimeoutException] is deliberately the failure type: the retry
/// layer treats it as retryable and the Sentry span mapper reports it as
/// deadline-exceeded, matching the header-timeout behavior.
@visibleForTesting
Stream<List<int>> inactivityWatchdogStream(
  Stream<List<int>> source, {
  required Duration inactivity,
}) {
  return source.timeout(
    inactivity,
    onTimeout: (sink) {
      sink.addError(
        TimeoutException(
          'catalog download stalled: no bytes received for '
          '${inactivity.inSeconds}s',
          inactivity,
        ),
      );
      sink.close();
    },
  );
}

ISentrySpan? _startCatalogSpan({
  required String operation,
  required String description,
  required String surface,
}) {
  try {
    final parent = Sentry.getSpan();
    final span =
        parent?.startChild(operation, description: description) ??
        Sentry.startTransaction(description, operation, bindToScope: false);
    span
      ..setTag('pg.surface', surface)
      ..setData('server.address', Uri.parse(SupabaseConfig.url).host)
      ..setData('storage.bucket', SupabaseContract.storageBucket);
    return span;
  } on Object {
    return null;
  }
}

Future<void> _finishCatalogSpan(ISentrySpan? span, SpanStatus status) async {
  if (span == null || span.finished) return;
  await span.finish(status: status);
}

SpanStatus _catalogSpanStatusForError(Object error, {SpanStatus? fallback}) {
  if (error is TimeoutException) return const SpanStatus.deadlineExceeded();
  if (error is PublicFetchDeniedException) {
    return SpanStatus.fromHttpStatusCode(error.statusCode);
  }
  if (error is CatalogVersionGateException) {
    return const SpanStatus.failedPrecondition();
  }
  return fallback == const SpanStatus.ok()
      ? const SpanStatus.unknownError()
      : fallback ?? const SpanStatus.unknownError();
}
