// Tests for scripts/verify_bundle.dart — bundle/storage alignment
// verifier (ADR-0001 P4).
//
// Mocks the HTTP layer via package:http/testing's MockClient. SQLite
// fixtures are real (in-memory or tmp file). No real Supabase, no
// network calls.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../scripts/verify_bundle.dart' as vb;

void main() {
  group('verify_bundle (P4)', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('verify_bundle_');
    });

    tearDown(() {
      try {
        tmpDir.deleteSync(recursive: true);
      } on Object {
        // tmp cleanup is best-effort
      }
    });

    String h(int i) {
      // 64-char lowercase hex hash (deterministic from int)
      return i.toRadixString(16).padLeft(64, '0');
    }

    String makeCatalog(List<MapEntry<String, String>> rows) {
      final dbPath = '${tmpDir.path}/pharmaguide_core.db';
      final db = sqlite3.open(dbPath);
      db.execute(
        'CREATE TABLE products_core ('
        '  dsld_id TEXT PRIMARY KEY, '
        '  detail_blob_sha256 TEXT)',
      );
      final stmt = db.prepare('INSERT INTO products_core VALUES (?, ?)');
      try {
        for (final r in rows) {
          stmt.execute([r.key, r.value]);
        }
      } finally {
        stmt.dispose();
      }
      db.dispose();
      return dbPath;
    }

    String writeManifest({
      required String dbVersion,
      required String dbPath,
      String? overrideChecksum,
    }) {
      final dbBytes = File(dbPath).readAsBytesSync();
      final checksum = overrideChecksum ?? sha256.convert(dbBytes).toString();
      final manifestPath = '${tmpDir.path}/export_manifest.json';
      File(manifestPath).writeAsStringSync(
        jsonEncode({'db_version': dbVersion, 'checksum_sha256': checksum}),
      );
      return manifestPath;
    }

    String validBlob(String dsldId) => jsonEncode({
      'dsld_id': dsldId,
      'ingredients': <dynamic>[],
      'warnings': <dynamic>[],
    });

    // -----------------------------------------------------------------
    // Test 1 — happy path: all blobs fetch + parse cleanly → passed
    // -----------------------------------------------------------------

    test('p4_happy_path_all_blobs_ok_returns_passed', () async {
      final dbPath = makeCatalog([
        for (var i = 0; i < 20; i++) MapEntry('${1000 + i}', h(i)),
      ]);
      final manifestPath = writeManifest(dbVersion: 'v1', dbPath: dbPath);
      final mockClient = MockClient(
        (request) async => http.Response(validBlob('test'), 200),
      );

      final result = await vb.verifyBundle(
        manifestPath: manifestPath,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'anon_key',
        sampleSize: 20,
        httpClient: mockClient,
      );

      expect(result.passed, isTrue, reason: result.summary());
      expect(result.failures, isEmpty);
      expect(result.sampleSize, 20);
      expect(result.dbVersion, 'v1');
      expect(result.checksumError, isNull);
    });

    // -----------------------------------------------------------------
    // Test 2 — checksum mismatch: short-circuits before any HTTP
    // -----------------------------------------------------------------

    test('p4_checksum_mismatch_short_circuits_before_any_http', () async {
      final dbPath = makeCatalog([MapEntry('1000', h(0))]);
      final manifestPath = writeManifest(
        dbVersion: 'v1',
        dbPath: dbPath,
        overrideChecksum: 'wrong_checksum_value',
      );

      var httpCalled = false;
      final mockClient = MockClient((request) async {
        httpCalled = true;
        return http.Response('{}', 200);
      });

      final result = await vb.verifyBundle(
        manifestPath: manifestPath,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'anon_key',
        sampleSize: 5,
        httpClient: mockClient,
      );

      expect(result.passed, isFalse);
      expect(result.checksumError, isNotNull);
      expect(result.checksumError, contains('does not match'));
      expect(result.checksumError, contains('git lfs pull'));
      expect(
        httpCalled,
        isFalse,
        reason: 'No HTTP call should fire when checksum mismatches',
      );
      expect(result.sampleSize, 0);
    });

    // -----------------------------------------------------------------
    // Test 3 — THE 2026-05-12 REGRESSION: 404 on every blob → fails
    // -----------------------------------------------------------------

    test(
      'p4_2026_05_12_regression_404_on_blobs_returns_failed_with_404_reason',
      () async {
        // Bundle references hashes that aren't in storage (Supabase orphan
        // cleanup deleted them). verify-bundle MUST catch this.
        final dbPath = makeCatalog([
          for (var i = 0; i < 5; i++) MapEntry('${1000 + i}', h(i)),
        ]);
        final manifestPath = writeManifest(
          dbVersion: 'v_stale',
          dbPath: dbPath,
        );
        final mockClient = MockClient(
          (request) async => http.Response('{"error":"Not found"}', 404),
        );

        final result = await vb.verifyBundle(
          manifestPath: manifestPath,
          dbPath: dbPath,
          supabaseUrl: 'https://test.supabase.co',
          anonKey: 'anon_key',
          sampleSize: 5,
          httpClient: mockClient,
        );

        expect(result.passed, isFalse);
        expect(result.failures.length, 5);
        for (final f in result.failures) {
          expect(f.reason, contains('404'));
          expect(f.reason, contains('2026-05-12'));
        }
      },
    );

    // -----------------------------------------------------------------
    // Test 4 — IDEMPOTENCY: same inputs → same sample (HR-9)
    // -----------------------------------------------------------------

    test('p4_idempotent_two_runs_same_inputs_select_same_hashes', () async {
      // 50 candidates, sample 10. Without a deterministic seed, two runs
      // would diverge.
      final dbPath = makeCatalog([
        for (var i = 0; i < 50; i++) MapEntry('${1000 + i}', h(i)),
      ]);
      final manifestPath = writeManifest(
        dbVersion: 'fixed_seed',
        dbPath: dbPath,
      );
      final mockClient = MockClient(
        (request) async => http.Response(validBlob('t'), 200),
      );

      final r1 = await vb.verifyBundle(
        manifestPath: manifestPath,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'k',
        sampleSize: 10,
        httpClient: mockClient,
      );
      final r2 = await vb.verifyBundle(
        manifestPath: manifestPath,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'k',
        sampleSize: 10,
        httpClient: mockClient,
      );

      expect(r1.sampledHashes.length, 10);
      expect(
        r1.sampledHashes,
        equals(r2.sampledHashes),
        reason:
            'Sample MUST be deterministic across runs '
            '(seed = SHA-256(db_version)).',
      );
    });

    // -----------------------------------------------------------------
    // Test 5 — different db_version → different sample (sanity check)
    // -----------------------------------------------------------------

    test('p4_different_db_version_yields_different_sample', () async {
      final dbPath = makeCatalog([
        for (var i = 0; i < 50; i++) MapEntry('${1000 + i}', h(i)),
      ]);
      final mockClient = MockClient(
        (request) async => http.Response(validBlob('t'), 200),
      );
      final manifestA = writeManifest(dbVersion: 'vA', dbPath: dbPath);

      final r1 = await vb.verifyBundle(
        manifestPath: manifestA,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'k',
        sampleSize: 10,
        httpClient: mockClient,
      );

      // Re-write the manifest with a different db_version. The DB content
      // is unchanged, so the checksum stays valid.
      final manifestB = writeManifest(dbVersion: 'vB', dbPath: dbPath);
      final r2 = await vb.verifyBundle(
        manifestPath: manifestB,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'k',
        sampleSize: 10,
        httpClient: mockClient,
      );

      expect(
        r1.sampledHashes,
        isNot(equals(r2.sampledHashes)),
        reason:
            'Different db_versions should produce different samples '
            '(seed input changed).',
      );
    });

    // -----------------------------------------------------------------
    // Test 6 — blob missing required top-level key → fails
    // -----------------------------------------------------------------

    test('p4_blob_missing_required_key_fails', () async {
      final dbPath = makeCatalog([MapEntry('1000', h(0))]);
      final manifestPath = writeManifest(dbVersion: 'v1', dbPath: dbPath);
      // Missing 'ingredients'
      final mockClient = MockClient(
        (request) async => http.Response(
          jsonEncode({'dsld_id': '1000', 'warnings': <dynamic>[]}),
          200,
        ),
      );

      final result = await vb.verifyBundle(
        manifestPath: manifestPath,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'k',
        sampleSize: 1,
        httpClient: mockClient,
      );

      expect(result.passed, isFalse);
      expect(result.failures.length, 1);
      expect(result.failures.first.reason, contains('ingredients'));
    });

    // -----------------------------------------------------------------
    // Test 7 — invalid JSON response → fails with parse error
    // -----------------------------------------------------------------

    test('p4_invalid_json_response_fails', () async {
      final dbPath = makeCatalog([MapEntry('1000', h(0))]);
      final manifestPath = writeManifest(dbVersion: 'v1', dbPath: dbPath);
      final mockClient = MockClient(
        (request) async => http.Response('NOT JSON {{{', 200),
      );

      final result = await vb.verifyBundle(
        manifestPath: manifestPath,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'k',
        sampleSize: 1,
        httpClient: mockClient,
      );

      expect(result.passed, isFalse);
      expect(result.failures.first.reason, contains('not valid JSON'));
    });

    // -----------------------------------------------------------------
    // Test 8 — Supabase URL + auth headers constructed correctly
    // -----------------------------------------------------------------

    test('p4_uses_correct_supabase_url_and_auth_headers', () async {
      final hash = 'abcdef0123456789' * 4; // 64 chars
      final dbPath = makeCatalog([MapEntry('1000', hash)]);
      final manifestPath = writeManifest(dbVersion: 'v1', dbPath: dbPath);

      Uri? capturedUrl;
      Map<String, String>? capturedHeaders;
      final mockClient = MockClient((request) async {
        capturedUrl = request.url;
        capturedHeaders = request.headers;
        return http.Response(validBlob('t'), 200);
      });

      await vb.verifyBundle(
        manifestPath: manifestPath,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'anon_key_xyz',
        sampleSize: 1,
        httpClient: mockClient,
      );

      expect(capturedUrl, isNotNull);
      expect(
        capturedUrl!.toString(),
        'https://test.supabase.co/storage/v1/object/pharmaguide/'
        'shared/details/sha256/ab/$hash.json',
      );
      expect(capturedHeaders!['Authorization'], 'Bearer anon_key_xyz');
      expect(capturedHeaders!['apikey'], 'anon_key_xyz');
    });

    // -----------------------------------------------------------------
    // Test 9 — manifest missing db_version → clear error
    // -----------------------------------------------------------------

    test('p4_manifest_missing_db_version_returns_clear_error', () async {
      final dbPath = makeCatalog([MapEntry('1000', h(0))]);
      final manifestPath = '${tmpDir.path}/export_manifest.json';
      File(
        manifestPath,
      ).writeAsStringSync(jsonEncode({'checksum_sha256': 'whatever'}));

      final result = await vb.verifyBundle(
        manifestPath: manifestPath,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'k',
        sampleSize: 1,
        httpClient: MockClient((_) async => http.Response('', 200)),
      );

      expect(result.passed, isFalse);
      expect(result.checksumError, contains('db_version'));
    });

    // -----------------------------------------------------------------
    // Test 10 — empty catalog (no products with detail_blob_sha256) → fails
    // -----------------------------------------------------------------

    test('p4_empty_catalog_returns_failed', () async {
      final dbPath = makeCatalog([]); // no rows
      final manifestPath = writeManifest(dbVersion: 'v1', dbPath: dbPath);

      final result = await vb.verifyBundle(
        manifestPath: manifestPath,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'k',
        sampleSize: 1,
        httpClient: MockClient((_) async => http.Response('', 200)),
      );

      expect(result.passed, isFalse);
      expect(result.checksumError, contains('no products'));
    });

    // -----------------------------------------------------------------
    // Test 11 — sample-size > population → samples whole population
    // -----------------------------------------------------------------

    test('p4_sample_size_larger_than_population_samples_all', () async {
      final dbPath = makeCatalog([
        for (var i = 0; i < 3; i++) MapEntry('${1000 + i}', h(i)),
      ]);
      final manifestPath = writeManifest(dbVersion: 'v1', dbPath: dbPath);
      final mockClient = MockClient(
        (request) async => http.Response(validBlob('t'), 200),
      );

      final result = await vb.verifyBundle(
        manifestPath: manifestPath,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'k',
        sampleSize: 100,
        httpClient: mockClient,
      );

      expect(result.passed, isTrue);
      expect(result.sampleSize, 3);
    });

    // -----------------------------------------------------------------
    // Test 12 — partial failure: some 200, some 404 → passes count, fails set
    // -----------------------------------------------------------------

    test('p4_partial_failure_records_only_failed_blobs', () async {
      final dbPath = makeCatalog([
        for (var i = 0; i < 5; i++) MapEntry('${1000 + i}', h(i)),
      ]);
      final manifestPath = writeManifest(dbVersion: 'v1', dbPath: dbPath);

      // Fail every other blob
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount += 1;
        if (callCount % 2 == 0) {
          return http.Response('{"error":"Not found"}', 404);
        }
        return http.Response(validBlob('t'), 200);
      });

      final result = await vb.verifyBundle(
        manifestPath: manifestPath,
        dbPath: dbPath,
        supabaseUrl: 'https://test.supabase.co',
        anonKey: 'k',
        sampleSize: 5,
        httpClient: mockClient,
      );

      expect(result.passed, isFalse);
      // 5 calls: positions 1,3,5 succeed; 2,4 fail → 2 failures
      expect(result.failures.length, 2);
      expect(result.sampleSize, 5);
    });
  });
}
