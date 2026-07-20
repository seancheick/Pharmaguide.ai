import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// Sentinel content for the fake live catalog file. Any test that asserts
/// this content survived proves the live catalog was not clobbered.
const _liveSentinel = 'LIVE-CATALOG-SENTINEL-BYTES';

const _dbVersion = '2026.06.10.020350';

/// Builds a minimal but structurally-valid catalog file the way the
/// pipeline would (same fixture shape as sync_service_test.dart): a
/// products_core row carrying export_version, an embedded export_manifest
/// key-value table, and user_version=3 so drift skips onCreate on open.
void _buildValidCatalog(String path, {String dbVersion = _dbVersion}) {
  final db = raw.sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE products_core ('
      'dsld_id TEXT, product_name TEXT, export_version TEXT, '
      'upc_sku TEXT, primary_category TEXT, quality_score_v4_100 REAL, '
      'quality_score_status TEXT, mapped_coverage REAL);',
    );
    db.execute("INSERT INTO products_core (export_version) VALUES ('2.0.0')");
    db.execute(
      'CREATE TABLE export_manifest (key TEXT PRIMARY KEY, value TEXT)',
    );
    db.execute("INSERT INTO export_manifest VALUES ('db_version', ?)", [
      dbVersion,
    ]);
    db.execute(
      "INSERT INTO export_manifest VALUES ('min_app_version', '1.0.0')",
    );
    db.execute(
      "INSERT INTO export_manifest VALUES ('schema_version', '2.0.0')",
    );
    db.execute('PRAGMA user_version = 3');
  } finally {
    db.dispose();
  }
}

String _readDbVersion(String path) {
  final db = raw.sqlite3.open(path);
  try {
    final rows = db.select(
      "SELECT value FROM export_manifest WHERE key = 'db_version'",
    );
    return rows.first['value'] as String;
  } finally {
    db.dispose();
  }
}

void main() {
  group('SyncService staged-catalog activation gate (boot safety)', () {
    late Directory tempDir;
    late String dbPath;
    late String stagingPath;
    late String markerPath;
    late String backupPath;
    late bool activatedCallbackRan;
    late SyncService svc;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sync_activation_test_');
      dbPath = '${tempDir.path}/pharmaguide_core.db';
      stagingPath = '$dbPath.staging';
      markerPath = '$dbPath.staging.version';
      backupPath = '$dbPath.backup';
      activatedCallbackRan = false;
      svc = SyncService(
        appVersion: '1.0.0',
        onCatalogActivated: () async => activatedCallbackRan = true,
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'staging WITH .staging.version marker is REFUSED at boot: live catalog '
      'preserved, partial + marker left in place for resume',
      () async {
        // The marker is written before the first downloaded byte and only
        // cleared after validation passes — its presence means "partial or
        // unvalidated". Simulate the OS killing the app mid-download.
        File(dbPath).writeAsStringSync(_liveSentinel);
        File(stagingPath).writeAsStringSync('truncated partial download');
        File(markerPath).writeAsStringSync(_dbVersion);

        await svc.activateStagedCoreDbAtPathForTest(dbPath, revalidate: true);

        expect(
          File(dbPath).readAsStringSync(),
          _liveSentinel,
          reason: 'an unvalidated partial must never clobber the live catalog',
        );
        expect(
          File(stagingPath).existsSync(),
          isTrue,
          reason: 'the partial must be kept so the next tick can Range-resume',
        );
        expect(
          File(markerPath).existsSync(),
          isTrue,
          reason: 'the resume bookkeeping marker must be kept alongside it',
        );
        expect(File(backupPath).existsSync(), isFalse);
        expect(activatedCallbackRan, isFalse);
      },
    );

    test('marker refusal also applies on the non-revalidating path '
        '(default parameters)', () async {
      File(dbPath).writeAsStringSync(_liveSentinel);
      File(stagingPath).writeAsStringSync('truncated partial download');
      File(markerPath).writeAsStringSync(_dbVersion);

      await svc.activateStagedCoreDbAtPathForTest(dbPath);

      expect(File(dbPath).readAsStringSync(), _liveSentinel);
      expect(File(stagingPath).existsSync(), isTrue);
      expect(File(markerPath).existsSync(), isTrue);
      expect(activatedCallbackRan, isFalse);
    });

    test('validated staging (marker cleared) IS activated at boot '
        '(revalidate: true) — happy path survives the hardening', () async {
      File(dbPath).writeAsStringSync(_liveSentinel);
      _buildValidCatalog(stagingPath);
      // No marker: stage-time validation cleared it.

      await svc.activateStagedCoreDbAtPathForTest(dbPath, revalidate: true);

      expect(
        _readDbVersion(dbPath),
        _dbVersion,
        reason: 'validated staging must be promoted to the live path',
      );
      expect(File(stagingPath).existsSync(), isFalse);
      expect(File(markerPath).existsSync(), isFalse);
      expect(File(backupPath).existsSync(), isFalse);
      expect(activatedCallbackRan, isTrue);
    });

    test(
      'validated staging activates on the in-session path too '
      '(default revalidate: false, as used by downloadCoreDb/CatalogSwapper)',
      () async {
        File(dbPath).writeAsStringSync(_liveSentinel);
        _buildValidCatalog(stagingPath);

        await svc.activateStagedCoreDbAtPathForTest(dbPath);

        expect(_readDbVersion(dbPath), _dbVersion);
        expect(File(stagingPath).existsSync(), isFalse);
        expect(activatedCallbackRan, isTrue);
      },
    );

    test('torn staging WITHOUT a marker is refused by boot revalidation: live '
        'catalog preserved, permanently-invalid staging deleted', () async {
      // Residual window: the marker bookkeeping is best-effort, so a
      // mid-download kill can leave a torn .staging with no marker. Boot
      // revalidation (integrity_check et al.) is the backstop.
      File(dbPath).writeAsStringSync(_liveSentinel);
      File(
        stagingPath,
      ).writeAsStringSync('this is not a sqlite database — torn mid-download');

      await svc.activateStagedCoreDbAtPathForTest(dbPath, revalidate: true);

      expect(
        File(dbPath).readAsStringSync(),
        _liveSentinel,
        reason: 'a file that fails revalidation must never be promoted',
      );
      expect(
        File(stagingPath).existsSync(),
        isFalse,
        reason:
            'a marker-less file that failed validation can never '
            'become valid — deleted, mirroring stageCoreDbDownload',
      );
      expect(File(markerPath).existsSync(), isFalse);
      expect(File(backupPath).existsSync(), isFalse);
      expect(activatedCallbackRan, isFalse);
    });

    test('no staging file present is a quiet no-op', () async {
      File(dbPath).writeAsStringSync(_liveSentinel);

      await svc.activateStagedCoreDbAtPathForTest(dbPath, revalidate: true);

      expect(File(dbPath).readAsStringSync(), _liveSentinel);
      expect(File(stagingPath).existsSync(), isFalse);
      expect(activatedCallbackRan, isFalse);
    });
  });
}
