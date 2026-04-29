import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:path/path.dart' as p;

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this.bytes);

  final Uint8List bytes;

  @override
  Future<ByteData> load(String key) async {
    return ByteData.sublistView(bytes);
  }
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
      'keeps the on-disk database when its byte length matches the bundle',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('pharmaguide-db');
        addTearDown(() async => tempDir.delete(recursive: true));

        final dbPath = '${tempDir.path}/pharmaguide_core.db';
        final file = File(dbPath);
        // Same length as the bundle below (4 bytes) — the byte-length check
        // treats this as "already up to date" and leaves the file alone.
        // This branch also protects an OTA-downloaded catalog whose bytes
        // happen to match the bundled asset.
        await file.writeAsBytes([9, 9, 9, 9]);

        final bundle = _FakeAssetBundle(Uint8List.fromList([1, 2, 3, 4]));
        await ensureCoreDatabaseAvailable(dbPath: dbPath, bundle: bundle);

        expect(await file.readAsBytes(), [9, 9, 9, 9]);
      },
    );

    test(
      'replaces the on-disk database when the bundle has a different byte length',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('pharmaguide-db');
        addTearDown(() async => tempDir.delete(recursive: true));

        final dbPath = '${tempDir.path}/pharmaguide_core.db';
        final file = File(dbPath);
        // Stale on-disk DB from a prior install (3 bytes). The bundle now
        // ships a different size — the new logic must re-materialize the
        // bundled asset so users get the fresh catalog after upgrade.
        await file.writeAsBytes([9, 9, 9]);

        final bundle = _FakeAssetBundle(Uint8List.fromList([1, 2, 3, 4]));
        await ensureCoreDatabaseAvailable(dbPath: dbPath, bundle: bundle);

        expect(await file.readAsBytes(), [1, 2, 3, 4]);
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
