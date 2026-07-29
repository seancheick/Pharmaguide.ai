import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/core/utils/app_version.dart';
import 'package:pharmaguide/services/catalog_version.dart';

/// Provides the singleton CoreDatabase instance (read-only product data).
/// Must be overridden at app startup with a real instance.
final coreDatabaseProvider = Provider<CoreDatabase>((ref) {
  throw UnimplementedError(
    'coreDatabaseProvider must be overridden at app startup',
  );
});

/// Provides the singleton UserDatabase instance.
/// Lazily opens the database on first access.
final userDatabaseProvider = Provider<UserDatabase>((ref) {
  throw UnimplementedError(
    'userDatabaseProvider must be overridden at app startup',
  );
});

/// Provides the singleton [InteractionDatabase] instance (read-only,
/// pipeline-built bundle). Must be overridden at app startup with a real
/// instance opened against the materialized bundled asset.
///
/// M3 contract: callers can read interaction rows synchronously through
/// the spec §7.3 lookup methods. The provider throws if the bundled asset
/// failed to materialize at boot — by design, so screens that depend on
/// medication-interaction data fail loud rather than silently miss
/// safety warnings.
final interactionDatabaseProvider = Provider<InteractionDatabase>((ref) {
  throw UnimplementedError(
    'interactionDatabaseProvider must be overridden at app startup',
  );
});

class InteractionDatabaseVersionGateException implements Exception {
  const InteractionDatabaseVersionGateException(this.message);

  final String message;

  @override
  String toString() => 'InteractionDatabaseVersionGateException: $message';
}

/// Refuses an interaction bundle this app cannot interpret. Missing or
/// malformed compatibility metadata is already rejected by
/// [InteractionDatabase.getMetadata]; present values fail closed here.
@visibleForTesting
void enforceInteractionDatabaseVersionGate({
  required String minAppVersion,
  required String schemaVersion,
  required String appVersion,
  int maxSupportedSchemaMajor = 1,
}) {
  final appComparison = compareSemver(minAppVersion, appVersion);
  if (appComparison == null) {
    throw InteractionDatabaseVersionGateException(
      'Interaction database min_app_version "$minAppVersion" is '
      'unparseable.',
    );
  }
  if (appComparison > 0) {
    throw InteractionDatabaseVersionGateException(
      'Interaction database requires app >= $minAppVersion; this build is '
      '$appVersion.',
    );
  }

  final schemaMajor = int.tryParse(schemaVersion.trim().split('.').first);
  if (schemaMajor == null || schemaMajor > maxSupportedSchemaMajor) {
    throw InteractionDatabaseVersionGateException(
      'Interaction database schema "$schemaVersion" is unsupported; '
      'this build supports up to $maxSupportedSchemaMajor.x.',
    );
  }
}

/// Catalog metadata from the embedded export_manifest — product count +
/// build date. Used by the home screen citation strip so the values stay
/// in sync with the actual bundled data instead of being hardcoded.
final catalogInfoProvider = FutureProvider<CatalogInfo>((ref) async {
  final db = ref.read(coreDatabaseProvider);
  final count = await db.countProducts();
  final generatedAt = await db.readManifestValue('generated_at');
  DateTime? buildDate;
  if (generatedAt != null && generatedAt.isNotEmpty) {
    buildDate = DateTime.tryParse(generatedAt);
  }
  return CatalogInfo(productCount: count, buildDate: buildDate);
});

class CatalogInfo {
  final int productCount;
  final DateTime? buildDate;
  const CatalogInfo({required this.productCount, this.buildDate});
}

const bundledCoreDatabaseAssetPath = 'assets/db/pharmaguide_core.db';
const bundledInteractionDatabaseAssetPath = 'assets/db/interaction_db.sqlite';
const bundledCoreDatabaseManifestAssetPath = 'assets/db/export_manifest.json';
const bundledInteractionDatabaseManifestAssetPath =
    'assets/db/interaction_db_manifest.json';

/// Ensures that a local core database exists before opening it.
///
/// The bundled asset must be the exact release snapshot that shipped with the
/// app. This path should never point to a partial/sample database in
/// production.
///
/// **Replacement on bundle upgrade.** When a new release ships a new bundled
/// DB, the previous on-disk copy may have the exact same byte length. We use
/// the bundled manifest checksum plus a local marker file; byte length alone
/// is never treated as proof that the local file is current.
Future<void> ensureCoreDatabaseAvailable({
  required String dbPath,
  AssetBundle? bundle,
}) async {
  await _ensureBundledDatabaseAvailable(
    dbPath: dbPath,
    bundle: bundle ?? rootBundle,
    dbAssetPath: bundledCoreDatabaseAssetPath,
    manifestAssetPath: bundledCoreDatabaseManifestAssetPath,
    preserveNewerExistingCoreDb: true,
  );
}

/// Force-restore the on-disk core DB from the bundled asset, ignoring
/// the byte-length cache check that [ensureCoreDatabaseAvailable] uses
/// for the cheap-path. Used by [openCoreDatabase]'s D4 rollback when
/// the live file is corrupt at the SQLite layer (the size may match
/// while the contents are unreadable).
Future<void> _restoreBundledCoreDatabase({
  required String dbPath,
  required AssetBundle bundle,
}) async {
  final assetData = await bundle.load(bundledCoreDatabaseAssetPath);
  final assetBytes = assetData.buffer.asUint8List(
    assetData.offsetInBytes,
    assetData.lengthInBytes,
  );
  await _writeBytesChunked(File(dbPath), assetBytes);
}

/// Chunk size for streamed asset → disk copies (4 MiB).
const int _assetWriteChunkBytes = 4 << 20;

/// Writes [bytes] to [file] in chunks via [File.openWrite].
///
/// `rootBundle.load` necessarily materializes the whole asset in memory
/// (Flutter assets have no streaming read API), but the disk write does
/// NOT need a second monolithic buffer: a single `writeAsBytes` of a
/// 100-250 MB catalog both double-buffers and blocks the event loop for
/// the whole write. Chunked writes through an IOSink keep peak memory at
/// one asset copy and yield to the event loop between chunks (the flush
/// awaits real I/O), so first-launch copy doesn't jank the UI isolate.
Future<void> _writeBytesChunked(File file, Uint8List bytes) async {
  await file.parent.create(recursive: true);
  final sink = file.openWrite();
  try {
    for (
      var offset = 0;
      offset < bytes.length;
      offset += _assetWriteChunkBytes
    ) {
      final end = math.min(offset + _assetWriteChunkBytes, bytes.length);
      sink.add(Uint8List.sublistView(bytes, offset, end));
      // Await the actual I/O so the event loop gets a turn per chunk.
      await sink.flush();
    }
  } finally {
    await sink.close();
  }
}

/// Opens the core catalog DB and probes it. If open or the structural
/// snapshot probe ([CoreDatabase.validateCatalogSnapshot]) throws, the
/// on-disk file is force-restored from the bundled asset and the open
/// is retried once.
///
/// **D4 rollback safety.** Bundle corruption (truncated OTA file,
/// schema drift, partial swap) must never brick the app. The bundled
/// asset is always available — it ships with the binary — and serves
/// as the always-good fallback. The retry runs against a known-good
/// file shape, so a second failure indicates the bundled asset itself
/// is broken (a build-gate problem, not a runtime one) and we let it
/// surface to the caller.
///
/// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track D, D4.
Future<CoreDatabase> openCoreDatabase({
  Directory? documentsDirectory,
  AssetBundle? bundle,
}) async {
  final dir = documentsDirectory ?? await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'pharmaguide_core.db');
  final assetBundle = bundle ?? rootBundle;
  await ensureCoreDatabaseAvailable(dbPath: dbPath, bundle: assetBundle);

  CoreDatabase? db;
  try {
    db = CoreDatabase.open(dbPath);
    await db.validateCatalogSnapshot();
    return db;
  } on Object catch (e) {
    // Telemetry payload is intentionally minimal: error type only,
    // no user data, no file path. Privacy: matches the contract in
    // CLAUDE.md ("never store health data in Supabase"). Sentry-side
    // grouping can key on the runtimeType bucket.
    debugPrint(
      '[catalog-rollback] core DB open/validate failed: '
      '${e.runtimeType} — restoring from bundled asset',
    );
    // Best-effort close of the failed handle so we don't leak it.
    if (db != null) {
      try {
        await db.close();
      } on Object {
        // Drift's open is lazy; the failed instance may not have a
        // live connection. Either way nothing to do here.
      }
    }
    await _restoreBundledCoreDatabase(dbPath: dbPath, bundle: assetBundle);
    final restored = CoreDatabase.open(dbPath);
    // Re-run the same structural probe the primary path uses. If the
    // bundled asset itself is corrupt (a build-gate failure), this throws
    // loudly here instead of letting a broken catalog limp into runtime
    // and fail silently downstream.
    await restored.validateCatalogSnapshot();
    return restored;
  }
}

/// Open the UserDatabase at the standard application documents path.
Future<UserDatabase> openUserDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'user_data.db');
  final db = UserDatabase.open(dbPath);
  // Fire-and-forget cache housekeeping — must never block or fail boot.
  unawaited(
    db.purgeExpiredCaches().catchError((Object e) {
      debugPrint('[user-db] purgeExpiredCaches failed: ${e.runtimeType}');
    }),
  );
  return db;
}

/// Ensures the bundled interaction database has been materialized to a
/// writable path the SQLite native library can open.
///
/// The interaction DB ships as a Flutter asset (built deterministically
/// by the M2 pipeline) and is read-only at runtime — but `NativeDatabase`
/// still needs a real file on disk, so we copy it out of the bundle once
/// on first launch and reuse the file thereafter.
///
/// **Replacement on bundle upgrade.** Uses the interaction DB manifest
/// checksum and a local marker file. Same-size asset updates are replaced;
/// the app never relies on byte length as a cache invalidation proxy.
Future<void> ensureInteractionDatabaseAvailable({
  required String dbPath,
  AssetBundle? bundle,
}) async {
  await _ensureBundledDatabaseAvailable(
    dbPath: dbPath,
    bundle: bundle ?? rootBundle,
    dbAssetPath: bundledInteractionDatabaseAssetPath,
    manifestAssetPath: bundledInteractionDatabaseManifestAssetPath,
  );
}

/// Materialize the bundled interaction asset (if needed) and open a
/// read-only [InteractionDatabase] against the on-disk copy.
///
/// Used by `main.dart` during bootstrap. The returned future completes
/// in well under 200 ms on a typical device — the asset is bundled, no
/// network call is involved, and the largest cost is the one-time
/// chunked copy to disk on first launch.
Future<InteractionDatabase> openInteractionDatabase({
  Directory? documentsDirectory,
  AssetBundle? bundle,
}) async {
  final dir = documentsDirectory ?? await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'interaction_db.sqlite');
  await ensureInteractionDatabaseAvailable(dbPath: dbPath, bundle: bundle);
  final db = InteractionDatabase.open(dbPath);
  try {
    final metadata = await db.getMetadata();
    enforceInteractionDatabaseVersionGate(
      minAppVersion: metadata.minAppVersion,
      schemaVersion: metadata.schemaVersion,
      appVersion: kAppVersion,
    );
    return db;
  } on Object {
    await db.close();
    rethrow;
  }
}

Future<void> _ensureBundledDatabaseAvailable({
  required String dbPath,
  required AssetBundle bundle,
  required String dbAssetPath,
  required String manifestAssetPath,
  bool preserveNewerExistingCoreDb = false,
}) async {
  final assetData = await bundle.load(dbAssetPath);
  final assetBytes = assetData.buffer.asUint8List(
    assetData.offsetInBytes,
    assetData.lengthInBytes,
  );
  final manifest = await _readBundledDbManifest(
    bundle: bundle,
    manifestAssetPath: manifestAssetPath,
  );
  // Fallback hash when the manifest carries no checksum (test fixtures).
  // Hashing 100-250 MB is pure CPU work — run it off the UI isolate.
  // Isolate.run copies the byte buffer into the worker; that one-time
  // copy is the price of not freezing frames for the hash duration.
  final String expectedChecksum =
      _manifestChecksum(manifest) ??
      await Isolate.run(() => sha256.convert(assetBytes).toString());
  final expectedVersion = manifest['db_version']?.toString();

  final dbFile = File(dbPath);
  final markerFile = File('$dbPath.bundle_marker.json');
  if (await dbFile.exists()) {
    if (await _markerMatches(
      markerFile: markerFile,
      dbAssetPath: dbAssetPath,
      expectedChecksum: expectedChecksum,
      expectedVersion: expectedVersion,
    )) {
      return;
    }

    final existingChecksum = await _sha256File(dbFile);
    if (existingChecksum == expectedChecksum) {
      await _writeBundleMarker(
        markerFile: markerFile,
        dbAssetPath: dbAssetPath,
        expectedChecksum: expectedChecksum,
        expectedVersion: expectedVersion,
      );
      return;
    }

    if (preserveNewerExistingCoreDb && expectedVersion != null) {
      final existingVersion = await _readCoreDbVersionIfAvailable(dbPath);
      final existingIsNewer = CatalogVersion.isRemoteNewer(
        remoteVersion: existingVersion,
        localVersion: expectedVersion,
      );
      if (existingIsNewer) {
        return;
      }
    }
  }

  await _writeBytesChunked(dbFile, assetBytes);
  await _writeBundleMarker(
    markerFile: markerFile,
    dbAssetPath: dbAssetPath,
    expectedChecksum: expectedChecksum,
    expectedVersion: expectedVersion,
  );
}

Future<Map<String, dynamic>> _readBundledDbManifest({
  required AssetBundle bundle,
  required String manifestAssetPath,
}) async {
  try {
    final raw = await bundle.loadString(manifestAssetPath);
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } on Object {
    // Release gates require this manifest. Tests can omit it and still
    // exercise checksum behavior by falling back to a computed asset hash.
  }
  return const <String, dynamic>{};
}

String? _manifestChecksum(Map<String, dynamic> manifest) {
  final raw = manifest['checksum_sha256'] ?? manifest['checksum'];
  if (raw == null) return null;
  final text = raw.toString();
  return text.startsWith('sha256:') ? text.substring('sha256:'.length) : text;
}

Future<bool> _markerMatches({
  required File markerFile,
  required String dbAssetPath,
  required String expectedChecksum,
  required String? expectedVersion,
}) async {
  if (!await markerFile.exists()) return false;
  try {
    final decoded = jsonDecode(await markerFile.readAsString());
    if (decoded is! Map<String, dynamic>) return false;
    return decoded['asset_path'] == dbAssetPath &&
        decoded['checksum_sha256'] == expectedChecksum &&
        decoded['db_version'] == expectedVersion;
  } on Object {
    return false;
  }
}

Future<void> _writeBundleMarker({
  required File markerFile,
  required String dbAssetPath,
  required String expectedChecksum,
  required String? expectedVersion,
}) async {
  await markerFile.parent.create(recursive: true);
  await markerFile.writeAsString(
    jsonEncode({
      'asset_path': dbAssetPath,
      'db_version': expectedVersion,
      'checksum_sha256': expectedChecksum,
    }),
    flush: true,
  );
}

Future<String> _sha256File(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

Future<String?> _readCoreDbVersionIfAvailable(String dbPath) async {
  CoreDatabase? db;
  try {
    db = CoreDatabase.open(dbPath);
    return await db.readDbVersion();
  } on Object {
    return null;
  } finally {
    if (db != null) {
      try {
        await db.close();
      } on Object {
        // Best-effort close only; a malformed DB can fail before Drift opens.
      }
    }
  }
}
