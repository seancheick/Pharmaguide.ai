import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:pharmaguide/core/utils/app_version.dart';

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

/// Canonical device-local Health History boundary. No second timeline store
/// or cloud mirror is registered anywhere else.
final healthEventRepositoryProvider = Provider<HealthEventRepository>((ref) {
  return HealthEventRepository(ref.watch(userDatabaseProvider));
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
void enforceInteractionDatabaseVersionGate({
  required String minAppVersion,
  required String schemaVersion,
  required String appVersion,
  int maxSupportedSchemaMajor = 4,
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

/// Open the UserDatabase at [dbPath], inside an account's folder.
Future<UserDatabase> openUserDatabase(String dbPath) async {
  final db = UserDatabase.open(dbPath);
  // Fire-and-forget cache housekeeping — must never block or fail boot.
  unawaited(
    db.purgeExpiredCaches().catchError((Object e) {
      debugPrint('[user-db] purgeExpiredCaches failed: ${e.runtimeType}');
    }),
  );
  return db;
}
