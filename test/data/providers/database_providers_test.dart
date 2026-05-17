import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:path/path.dart' as p;

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this.bytes, {Map<String, List<int>> assets = const {}})
    : assets = {
        bundledCoreDatabaseAssetPath: bytes,
        bundledInteractionDatabaseAssetPath: bytes,
        ...assets,
      };

  final Uint8List bytes;
  final Map<String, List<int>> assets;

  @override
  Future<ByteData> load(String key) async {
    final asset = assets[key];
    if (asset == null) {
      throw StateError('missing fake asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(asset));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final asset = assets[key];
    if (asset == null) {
      throw StateError('missing fake asset: $key');
    }
    return utf8.decode(asset);
  }
}

List<int> _manifestBytes({
  required String dbVersion,
  required List<int> dbBytes,
}) {
  return utf8.encode(
    jsonEncode({
      'db_version': dbVersion,
      'checksum_sha256': sha256.convert(dbBytes).toString(),
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ensureCoreDatabaseAvailable', () {
    test(
      'copies the bundled database when the local file is missing',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('pharmaguide-db');
        addTearDown(() async => tempDir.delete(recursive: true));

        final dbPath = '${tempDir.path}/pharmaguide_core.db';
        final bundle = _FakeAssetBundle(Uint8List.fromList([1, 2, 3, 4]));

        await ensureCoreDatabaseAvailable(dbPath: dbPath, bundle: bundle);

        final file = File(dbPath);
        expect(await file.exists(), isTrue);
        expect(await file.readAsBytes(), [1, 2, 3, 4]);
      },
    );

    test(
      'keeps the on-disk database when checksum marker matches bundle',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('pharmaguide-db');
        addTearDown(() async => tempDir.delete(recursive: true));

        final dbPath = '${tempDir.path}/pharmaguide_core.db';
        final file = File(dbPath);
        final bytes = [1, 2, 3, 4];
        await file.writeAsBytes(bytes);

        final bundle = _FakeAssetBundle(
          Uint8List.fromList(bytes),
          assets: {
            'assets/db/export_manifest.json': _manifestBytes(
              dbVersion: '2026.05.17.204805',
              dbBytes: bytes,
            ),
          },
        );
        await ensureCoreDatabaseAvailable(dbPath: dbPath, bundle: bundle);

        expect(await file.readAsBytes(), bytes);
      },
    );

    test(
      'replaces same-length on-disk database when checksum differs',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('pharmaguide-db');
        addTearDown(() async => tempDir.delete(recursive: true));

        final dbPath = '${tempDir.path}/pharmaguide_core.db';
        final file = File(dbPath);
        await file.writeAsBytes([9, 9, 9, 9]);

        final bundleBytes = [1, 2, 3, 4];
        final bundle = _FakeAssetBundle(
          Uint8List.fromList(bundleBytes),
          assets: {
            'assets/db/export_manifest.json': _manifestBytes(
              dbVersion: '2026.05.17.204805',
              dbBytes: bundleBytes,
            ),
          },
        );
        await ensureCoreDatabaseAvailable(dbPath: dbPath, bundle: bundle);

        expect(await file.readAsBytes(), bundleBytes);
      },
    );

    test(
      'preserves a validated newer OTA core database over an older bundle',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('pharmaguide-db');
        addTearDown(() async => tempDir.delete(recursive: true));

        final assetData = await rootBundle.load(bundledCoreDatabaseAssetPath);
        final assetBytes = assetData.buffer.asUint8List(
          assetData.offsetInBytes,
          assetData.lengthInBytes,
        );
        final dbPath = p.join(tempDir.path, 'pharmaguide_core.db');
        final file = File(dbPath);
        await file.writeAsBytes(assetBytes, flush: true);

        final db = CoreDatabase.open(dbPath);
        await db.customStatement(
          "UPDATE export_manifest SET value = '2099.01.01.000000' "
          "WHERE key = 'db_version'",
        );
        await db.close();
        final newerBytes = await file.readAsBytes();

        await ensureCoreDatabaseAvailable(dbPath: dbPath, bundle: rootBundle);

        expect(await file.readAsBytes(), newerBytes);
      },
    );
  });

  group('ensureInteractionDatabaseAvailable', () {
    test(
      'replaces same-length on-disk interaction DB when checksum differs',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'pharmaguide-idb',
        );
        addTearDown(() async => tempDir.delete(recursive: true));

        final dbPath = '${tempDir.path}/interaction_db.sqlite';
        final file = File(dbPath);
        await file.writeAsBytes([9, 9, 9, 9]);

        final bundleBytes = [1, 2, 3, 4];
        final bundle = _FakeAssetBundle(
          Uint8List.fromList(bundleBytes),
          assets: {
            'assets/db/interaction_db_manifest.json': _manifestBytes(
              dbVersion: '1.0.0',
              dbBytes: bundleBytes,
            ),
          },
        );

        await ensureInteractionDatabaseAvailable(
          dbPath: dbPath,
          bundle: bundle,
        );

        expect(await file.readAsBytes(), bundleBytes);
      },
    );
  });

  // -------------------------------------------------------------------------
  // D4 — bootstrap-time rollback safety.
  //
  // Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track D, D4. Bundle
  // corruption (truncated OTA file, schema drift, partial swap) must
  // never brick the app. `openCoreDatabase` probes the on-disk file
  // via `validateCatalogSnapshot()` and force-restores from the
  // bundled asset on any failure.
  //
  // These tests use the REAL bundled asset (via `rootBundle`) because
  // building a synthetic-but-valid SQLite file with the full
  // products_core schema and a populated export_manifest table is
  // strictly more code than just consuming the deterministic bundle
  // the release-gate test (`bundled_catalog_test.dart`) already
  // guarantees is good. If the bundle is missing or invalid, those
  // gates fail before this suite is reached.
  // -------------------------------------------------------------------------
  group('openCoreDatabase rollback safety', () {
    test(
      'happy path: a healthy on-disk DB opens without firing the fallback',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('pgdb-d4-ok');
        addTearDown(() async => tempDir.delete(recursive: true));

        // No pre-existing file at the path. `ensureCoreDatabaseAvailable`
        // copies the real bundled asset in, the probe succeeds, no
        // restore is triggered.
        final db = await openCoreDatabase(documentsDirectory: tempDir);
        addTearDown(() async => db.close());

        final productCount = await db.countProducts();
        expect(
          productCount,
          greaterThan(0),
          reason:
              'happy-path open returned a DB with no products — the '
              'probe should have rejected an empty catalog',
        );
      },
    );

    test('corruption fallback: byte-length-matched garbage on disk → restore '
        'from bundle, retry open, return a working DB', () async {
      final tempDir = await Directory.systemTemp.createTemp('pgdb-d4-bad');
      addTearDown(() async => tempDir.delete(recursive: true));

      // Pre-populate the live path with garbage that has the SAME byte
      // length as the bundled asset. This is the hard-to-detect case:
      // `ensureCoreDatabaseAvailable`'s cheap-path size-match check
      // skips the overwrite, so without the D4 probe the app would
      // hand the corrupted file to Drift and crash on first query.
      final assetData = await rootBundle.load(bundledCoreDatabaseAssetPath);
      final assetBytes = assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      );
      final dbPath = p.join(tempDir.path, 'pharmaguide_core.db');
      final dbFile = File(dbPath);
      // 0xff repeated to the bundle's exact length — definitely not
      // a valid SQLite header (the SQLite magic is "SQLite format 3\x00")
      // but the size check still passes.
      await dbFile.writeAsBytes(
        List<int>.filled(assetBytes.length, 0xff),
        flush: true,
      );
      expect(await dbFile.length(), assetBytes.length);

      // Open should detect the corruption via validateCatalogSnapshot,
      // force-restore from the bundled asset, and return a working DB.
      final db = await openCoreDatabase(documentsDirectory: tempDir);
      addTearDown(() async => db.close());

      final productCount = await db.countProducts();
      expect(
        productCount,
        greaterThan(0),
        reason:
            'rollback path returned a DB but countProducts came '
            'back zero — the bundle restore did not happen',
      );

      // After rollback the file length should match the bundled
      // asset (proves the restore overwrote the garbage), and we
      // already proved above that countProducts succeeds (proves
      // the new file is a real SQLite catalog). We don't byte-compare
      // because Drift's beforeOpen migration bumps the SQLite
      // file change counter at offset 24-27 the first time
      // countProducts runs against the restored file.
      expect(
        await dbFile.length(),
        assetBytes.length,
        reason:
            'after rollback, the on-disk file size should match '
            'the bundled asset (was overwritten verbatim, then opened)',
      );
    });

    test(
      'first-launch path: no on-disk file → bundle materializes via '
      'ensureCoreDatabaseAvailable, probe passes, no rollback fires',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('pgdb-d4-new');
        addTearDown(() async => tempDir.delete(recursive: true));

        final dbPath = p.join(tempDir.path, 'pharmaguide_core.db');
        expect(await File(dbPath).exists(), isFalse);

        final db = await openCoreDatabase(documentsDirectory: tempDir);
        addTearDown(() async => db.close());

        expect(await File(dbPath).exists(), isTrue);
        expect(await db.countProducts(), greaterThan(0));
      },
    );
  });
}
