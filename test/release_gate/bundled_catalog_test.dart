// Release gate: the Flutter bundle must ship a real, verified catalog.
//
// This test is the last line of defense against a broken release. If any
// check in this file fails, the build should not ship. It runs against
// the actual `assets/db/pharmaguide_core.db` file imported by
// `scripts/import_catalog_artifact.sh`, not a fixture.
//
// What it verifies:
//
// 1. `assets/db/pharmaguide_core.db` is declared in pubspec.yaml, loadable
//    via rootBundle, and at least 1 MiB (catches 4-byte test fixtures
//    from `database_providers_test.dart` accidentally shipping).
// 2. `assets/db/export_manifest.json` is declared, loadable, well-formed,
//    and has every field the bridge script guarantees.
// 3. The bundled SQLite file opens cleanly via the same `CoreDatabase`
//    wrapper the production app uses.
// 4. `products_core` has at least 2000 rows.
// 5. At least one row has a populated `export_version`.
// 6. `CoreDatabase.validateCatalogSnapshot()` returns the catalog's
//    `db_version`, and that value matches the bundled JSON manifest.
// 7. `CoreDatabase.readExportVersion()` returns the catalog's
//    `schema_version`, and that value matches the bundled JSON manifest.
//
// Run with: flutter test test/release_gate/bundled_catalog_test.dart

@Tags(['bundle'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/core_database.dart';

const _minBundledDbBytes = 1024 * 1024; // 1 MiB
const _minProductCount = 2000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('release gate: bundled catalog asset', () {
    test('catalog importer accepts structured-warning schema 2.1.0', () {
      final importer = File(
        'scripts/import_catalog_artifact.sh',
      ).readAsStringSync();
      final supportedSchemas = RegExp(
        r'APP_SUPPORTED_SCHEMAS=\(([^)]*)\)',
      ).firstMatch(importer)?.group(1);

      expect(
        supportedSchemas,
        contains('"2.1.0"'),
        reason:
            'Pipeline schema 2.1.0 emits structured top_warnings, which '
            'this app already parses. Keep the local import gate aligned '
            'with the catalog runtime compatibility contract.',
      );
    });

    test('catalog importer accepts typed-safety schema 2.3.0', () {
      final importer = File(
        'scripts/import_catalog_artifact.sh',
      ).readAsStringSync();
      final supportedSchemas = RegExp(
        r'APP_SUPPORTED_SCHEMAS=\(([^)]*)\)',
      ).firstMatch(importer)?.group(1);

      expect(
        supportedSchemas,
        contains('"2.3.0"'),
        reason:
            'Pipeline schema 2.3.0 emits the product_safety_status and '
            'quality_assessment_status columns this app already reads, plus '
            'typed dose-safety detail. Keep the local import gate aligned '
            'with the catalog runtime compatibility contract.',
      );
    });

    test(
      'assets/db/pharmaguide_core.db is declared, loadable, and non-trivial',
      () async {
        final data = await rootBundle.load('assets/db/pharmaguide_core.db');
        expect(
          data.lengthInBytes,
          greaterThan(_minBundledDbBytes),
          reason:
              'The bundled catalog is only ${data.lengthInBytes} bytes. A '
              'real pipeline release should be at least 1 MiB. Did you '
              'forget to run scripts/import_catalog_artifact.sh?',
        );
      },
    );

    test(
      'assets/db/export_manifest.json is declared, loadable, and well-formed',
      () async {
        final raw = await rootBundle.loadString(
          'assets/db/export_manifest.json',
        );
        final manifest = json.decode(raw) as Map<String, dynamic>;

        for (final key in const [
          'db_version',
          'schema_version',
          'pipeline_version',
          'scoring_version',
          'product_count',
          'min_app_version',
          'checksum_sha256',
          'generated_at',
        ]) {
          expect(
            manifest.containsKey(key),
            isTrue,
            reason: 'bundled manifest is missing required key: $key',
          );
        }

        // Sanity: checksum is 64 hex chars (raw sha256, no "sha256:" prefix).
        final checksum = manifest['checksum_sha256'] as String;
        expect(
          RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum),
          isTrue,
          reason:
              'checksum_sha256 in bundled manifest is not a 64-char hex '
              'string: "$checksum"',
        );
      },
    );

    test('bundled SQLite opens via CoreDatabase, has enough rows, and both '
        'versions agree with the bundled JSON manifest', () async {
      // Materialize the asset to a temp file so CoreDatabase can open it
      // — NativeDatabase cannot read from in-memory ByteData directly.
      final tmpDir = await Directory.systemTemp.createTemp('rg-bundle');
      addTearDown(() => tmpDir.delete(recursive: true));

      final data = await rootBundle.load('assets/db/pharmaguide_core.db');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final dbFile = File(p.join(tmpDir.path, 'pharmaguide_core.db'));
      await dbFile.writeAsBytes(bytes, flush: true);

      final rawJson = await rootBundle.loadString(
        'assets/db/export_manifest.json',
      );
      final manifest = json.decode(rawJson) as Map<String, dynamic>;

      final db = CoreDatabase.open(dbFile.path);
      try {
        final productCount = await db.countProducts();
        expect(
          productCount,
          greaterThanOrEqualTo(_minProductCount),
          reason:
              'products_core has $productCount rows, release gate '
              'requires at least $_minProductCount',
        );

        final schemaVersion = await db.readExportVersion();
        expect(
          schemaVersion,
          isNotNull,
          reason: 'no products_core rows have a populated export_version',
        );
        expect(
          schemaVersion,
          equals(manifest['schema_version']),
          reason:
              'schema_version disagrees between bundled JSON manifest '
              '(${manifest['schema_version']}) and SQLite products_core '
              '($schemaVersion)',
        );

        final dbVersion = await db.readDbVersion();
        expect(
          dbVersion,
          isNotNull,
          reason:
              'bundled DB is missing embedded export_manifest.db_version '
              '— was it produced by build_final_db.py v1.3.2+?',
        );
        expect(
          dbVersion,
          equals(manifest['db_version']),
          reason:
              'db_version disagrees between bundled JSON manifest '
              '(${manifest['db_version']}) and embedded SQLite '
              'export_manifest table ($dbVersion)',
        );

        // The primary contract of validateCatalogSnapshot: it returns the
        // freshness version callers should compare against remote
        // manifests. For a v1.3.2+ DB that is db_version, not
        // export_version.
        final validated = await db.validateCatalogSnapshot();
        expect(
          validated,
          equals(dbVersion),
          reason:
              'validateCatalogSnapshot must return db_version (the build '
              'freshness version) for v1.3.2+ catalogs',
        );
      } finally {
        await db.close();
      }
    });
  });
}
