import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';

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
const bundledInteractionDatabaseAssetPath =
    'assets/db/interaction_db.sqlite';

/// Ensures that a local core database exists before opening it.
///
/// The bundled asset must be the exact release snapshot that shipped with the
/// app. This path should never point to a partial/sample database in
/// production.
///
/// **Replacement on bundle upgrade.** When a new release ships a new
/// `assets/db/pharmaguide_core.db`, the existing on-disk copy from a prior
/// install is stale. We detect this by comparing byte length — same length
/// means we keep the existing file (cheap path, preserves any OTA-downloaded
/// catalog that's a byte-identical match for the bundle), different length
/// means we re-materialize from the bundled asset.
///
/// This mirrors the pattern used by [ensureInteractionDatabaseAvailable].
/// Trade-off: in the rare case a user OTA-downloaded a catalog that's newer
/// than the bundle they later install, this will regress them to the bundle
/// version for one session — `_refreshCatalogIfNeeded` will detect the
/// remote-is-newer state on next launch and re-stage the OTA download.
Future<void> ensureCoreDatabaseAvailable({
  required String dbPath,
  AssetBundle? bundle,
}) async {
  final dbFile = File(dbPath);
  final assetData =
      await (bundle ?? rootBundle).load(bundledCoreDatabaseAssetPath);
  final assetBytes = assetData.buffer
      .asUint8List(assetData.offsetInBytes, assetData.lengthInBytes);

  if (await dbFile.exists()) {
    final existingLength = await dbFile.length();
    if (existingLength == assetBytes.lengthInBytes) {
      return; // Up to date.
    }
  }

  await dbFile.parent.create(recursive: true);
  await dbFile.writeAsBytes(assetBytes, flush: true);
}

Future<CoreDatabase> openCoreDatabase({
  Directory? documentsDirectory,
  AssetBundle? bundle,
}) async {
  final dir = documentsDirectory ?? await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'pharmaguide_core.db');
  await ensureCoreDatabaseAvailable(dbPath: dbPath, bundle: bundle);
  return CoreDatabase.open(dbPath);
}

/// Open the UserDatabase at the standard application documents path.
Future<UserDatabase> openUserDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'user_data.db');
  return UserDatabase.open(dbPath);
}

/// Ensures the bundled interaction database has been materialized to a
/// writable path the SQLite native library can open.
///
/// The interaction DB ships as a Flutter asset (built deterministically
/// by the M2 pipeline) and is read-only at runtime — but `NativeDatabase`
/// still needs a real file on disk, so we copy it out of the bundle once
/// on first launch and reuse the file thereafter.
///
/// **Replacement on bundle upgrade.** When a new release ships a new
/// `assets/db/interaction_db.sqlite`, the existing on-disk copy is
/// stale. We detect this by comparing byte length — same length means we
/// keep the existing file (cheap path), different length means we
/// re-materialize. This is a cheap proxy: if the size changes the file
/// is definitely different, and if size matches but content is somehow
/// different we'll catch it at the next bundle build because the
/// pipeline guarantees byte-stable rebuilds.
///
/// Note: a stronger approach is comparing the bundled manifest's
/// checksum_sha256 to a stored marker — that's wired up by the import
/// gate (Gate I3) at build time, so a corrupt asset can never reach the
/// device in the first place. The size check here is purely a cache
/// invalidation hint, not a security gate.
Future<void> ensureInteractionDatabaseAvailable({
  required String dbPath,
  AssetBundle? bundle,
}) async {
  final dbFile = File(dbPath);
  final assetData =
      await (bundle ?? rootBundle).load(bundledInteractionDatabaseAssetPath);
  final assetBytes = assetData.buffer
      .asUint8List(assetData.offsetInBytes, assetData.lengthInBytes);

  if (await dbFile.exists()) {
    final existingLength = await dbFile.length();
    if (existingLength == assetBytes.lengthInBytes) {
      return; // Up to date.
    }
  }

  await dbFile.parent.create(recursive: true);
  await dbFile.writeAsBytes(assetBytes, flush: true);
}

/// Materialize the bundled interaction asset (if needed) and open a
/// read-only [InteractionDatabase] against the on-disk copy.
///
/// Used by `main.dart` during bootstrap. The returned future completes
/// in well under 200 ms on a typical device — the asset is bundled, no
/// network call is involved, and the largest cost is the one-time
/// `writeAsBytes` on first launch.
Future<InteractionDatabase> openInteractionDatabase({
  Directory? documentsDirectory,
  AssetBundle? bundle,
}) async {
  final dir = documentsDirectory ?? await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'interaction_db.sqlite');
  await ensureInteractionDatabaseAvailable(dbPath: dbPath, bundle: bundle);
  return InteractionDatabase.open(dbPath);
}
