import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// Builds a minimal but structurally-valid staged catalog file the way the
/// pipeline would: a products_core row carrying export_version and an
/// embedded export_manifest key-value table. user_version=3 matches
/// CoreDatabase.schemaVersion so drift skips onCreate on open.
void _buildStagedCatalog(
  String path, {
  required String dbVersion,
  String? minAppVersion,
  String? schemaVersion,
}) {
  final db = raw.sqlite3.open(path);
  try {
    db.execute('''
      CREATE TABLE products_core (
        export_version TEXT,
        upc_sku TEXT,
        primary_category TEXT,
        quality_score_v4_100 REAL,
        quality_score_status TEXT
      );
    ''');
    db.execute("INSERT INTO products_core (export_version) VALUES ('2.0.0')");
    db.execute(
      'CREATE TABLE export_manifest (key TEXT PRIMARY KEY, value TEXT)',
    );
    db.execute("INSERT INTO export_manifest VALUES ('db_version', ?)", [
      dbVersion,
    ]);
    if (minAppVersion != null) {
      db.execute("INSERT INTO export_manifest VALUES ('min_app_version', ?)", [
        minAppVersion,
      ]);
    }
    if (schemaVersion != null) {
      db.execute("INSERT INTO export_manifest VALUES ('schema_version', ?)", [
        schemaVersion,
      ]);
    }
    db.execute('PRAGMA user_version = 3');
  } finally {
    db.dispose();
  }
}

void main() {
  group('SyncService.isUpdateAvailable', () {
    test('remote newer than local returns true', () async {
      final svc = SyncService(
        currentDbVersionFetcher: () async => '2026.05.17.204805',
      );

      expect(await svc.isUpdateAvailable('2026.05.17.171456'), isTrue);
    });

    test('remote equal to local returns false', () async {
      final svc = SyncService(
        currentDbVersionFetcher: () async => '2026.05.17.204805',
      );

      expect(await svc.isUpdateAvailable('2026.05.17.204805'), isFalse);
    });

    test('remote older than local returns false', () async {
      final svc = SyncService(
        currentDbVersionFetcher: () async => '2026.05.17.171456',
      );

      expect(
        await svc.isUpdateAvailable('2026.05.17.204805'),
        isFalse,
        reason: 'OTA must never downgrade a newer bundled catalog',
      );
    });

    test('malformed remote or local version fails closed', () async {
      final malformedRemote = SyncService(
        currentDbVersionFetcher: () async => 'latest',
      );
      expect(
        await malformedRemote.isUpdateAvailable('2026.05.17.204805'),
        isFalse,
      );

      final malformedLocal = SyncService(
        currentDbVersionFetcher: () async => '2026.05.17.204805',
      );
      expect(await malformedLocal.isUpdateAvailable('local-dev'), isFalse);
    });
  });

  group('SyncService.enforceCatalogVersionGate', () {
    test('min_app_version above current app version is refused', () {
      expect(
        () => SyncService.enforceCatalogVersionGate(
          minAppVersion: '99.0.0',
          schemaVersion: '2.0.0',
          appVersion: '1.0.0',
        ),
        throwsA(isA<CatalogVersionGateException>()),
      );
    });

    test('min_app_version equal to or below app version is allowed', () {
      SyncService.enforceCatalogVersionGate(
        minAppVersion: '1.0.0',
        schemaVersion: '2.0.0',
        appVersion: '1.0.0',
      );
      SyncService.enforceCatalogVersionGate(
        minAppVersion: '0.9.5',
        schemaVersion: '1.6.0',
        appVersion: '1.0.0',
      );
    });

    test('unsupported schema major is refused', () {
      expect(
        () => SyncService.enforceCatalogVersionGate(
          minAppVersion: '1.0.0',
          schemaVersion: '3.0.0',
          appVersion: '1.0.0',
          maxSupportedSchemaMajor: 2,
        ),
        throwsA(isA<CatalogVersionGateException>()),
      );
    });

    test('missing keys fail open (older catalogs predate them)', () {
      SyncService.enforceCatalogVersionGate(
        minAppVersion: null,
        schemaVersion: null,
        appVersion: '1.0.0',
      );
    });

    test('present-but-malformed values fail closed', () {
      expect(
        () => SyncService.enforceCatalogVersionGate(
          minAppVersion: 'not-a-version',
          schemaVersion: null,
          appVersion: '1.0.0',
        ),
        throwsA(isA<CatalogVersionGateException>()),
      );
      expect(
        () => SyncService.enforceCatalogVersionGate(
          minAppVersion: null,
          schemaVersion: 'banana',
          appVersion: '1.0.0',
        ),
        throwsA(isA<CatalogVersionGateException>()),
      );
    });
  });

  group('SyncService staged-DB validation (version gate end-to-end)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sync_service_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('staged DB with min_app_version 99.0.0 is refused', () async {
      const dbVersion = '2026.06.10.020350';
      final stagingPath = '${tempDir.path}/pharmaguide_core.db.staging';
      _buildStagedCatalog(
        stagingPath,
        dbVersion: dbVersion,
        minAppVersion: '99.0.0',
        schemaVersion: '2.0.0',
      );

      final svc = SyncService(appVersion: '1.0.0');
      await expectLater(
        svc.validateStagedDatabaseForTest(
          stagingPath,
          expectedVersion: dbVersion,
        ),
        throwsA(isA<CatalogVersionGateException>()),
      );
    });

    test(
      'staged DB with compatible manifest validates and returns version',
      () async {
        const dbVersion = '2026.06.10.020350';
        final stagingPath = '${tempDir.path}/pharmaguide_core.db.staging';
        _buildStagedCatalog(
          stagingPath,
          dbVersion: dbVersion,
          minAppVersion: '1.0.0',
          schemaVersion: '2.0.0',
        );

        final svc = SyncService(appVersion: '1.0.0');
        expect(
          await svc.validateStagedDatabaseForTest(
            stagingPath,
            expectedVersion: dbVersion,
          ),
          dbVersion,
        );
      },
    );

    test(
      'staged DB without gate keys (older catalog) still validates',
      () async {
        const dbVersion = '2026.06.10.020350';
        final stagingPath = '${tempDir.path}/pharmaguide_core.db.staging';
        _buildStagedCatalog(stagingPath, dbVersion: dbVersion);

        final svc = SyncService(appVersion: '1.0.0');
        expect(
          await svc.validateStagedDatabaseForTest(
            stagingPath,
            expectedVersion: dbVersion,
          ),
          dbVersion,
        );
      },
    );
  });
}
