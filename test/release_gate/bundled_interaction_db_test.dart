// Release gate: the Flutter bundle must ship a real, verified interaction
// database alongside its JSON manifest, and the boot-time materialization
// path must complete in well under 200 ms on the test host.
//
// This complements `bundled_catalog_test.dart` for the catalog DB. If any
// check in this file fails, the build should not ship — a missing or
// stale interaction bundle would silently disable medication safety
// warnings.
//
// What it verifies:
//
// 1. `assets/db/interaction_db.sqlite` is declared, loadable, and at
//    least 16 KiB (catches a placeholder/empty file accidentally
//    shipping; the real bundle is ~hundreds of KiB).
// 2. `assets/db/interaction_db_manifest.json` is declared, parseable,
//    and has every required key the import gate guarantees.
// 3. The bundled SQLite opens through the production
//    `openInteractionDatabase` helper, hitting the same
//    `ensureInteractionDatabaseAvailable` materialization path the app
//    uses at boot.
// 4. The end-to-end materialize-and-open path completes in <200 ms.
//    This is the spec §11.3 startup-budget guard from the F8 plan.
// 5. `getMetadata()` hydrates and the embedded
//    `interaction_db_metadata.schema_version` and `total_interactions`
//    keys agree with the JSON manifest.
// 6. `countLiveInteractions()` returns at least 1 row.
//
// Run with: flutter test test/release_gate/bundled_interaction_db_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

// 16 KiB — well above the 4-byte test fixture and far below the real
// pipeline output. The bundle ships ~half a MiB today; this lower bound
// is intentionally permissive so we don't have to bump it on every
// curated-row addition.
const _minBundledInteractionDbBytes = 16 * 1024;

// 200 ms is the F8 startup budget for asset materialization + open.
// The asset is small and the only I/O is one writeAsBytes + a
// `NativeDatabase` open, so even on slow CI hosts this should be
// comfortable. Bumping this number is a regression — investigate
// instead.
const _maxBootMaterializeMs = 200;

// Keys the pipeline writes to interaction_db_manifest.json (file/transport
// metadata only). Build-process counters like `override_count` and
// `resolved_conflict_count` live in the embedded `interaction_db_metadata`
// kv table inside the SQLite, not in the JSON sidecar — they're verified
// by the metadata-agreement test below via `getMetadata()`.
const _requiredManifestKeys = <String>[
  'built_at',
  'checksum_sha256',
  'schema_version',
  'db_version',
  'total_interactions',
  'source_drafts_count',
  'source_suppai_count',
  'interaction_db_version',
  'pipeline_version',
  'min_app_version',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('release gate: bundled interaction DB asset', () {
    test(
      'assets/db/interaction_db.sqlite is declared, loadable, and non-trivial',
      () async {
        final data = await rootBundle.load('assets/db/interaction_db.sqlite');
        expect(
          data.lengthInBytes,
          greaterThan(_minBundledInteractionDbBytes),
          reason:
              'The bundled interaction DB is only ${data.lengthInBytes} '
              'bytes. A real pipeline release should be at least '
              '$_minBundledInteractionDbBytes bytes. Did you forget to run '
              'scripts/import_catalog_artifact.sh?',
        );
      },
    );

    test(
      'assets/db/interaction_db_manifest.json is declared, loadable, '
      'and well-formed',
      () async {
        final raw = await rootBundle.loadString(
          'assets/db/interaction_db_manifest.json',
        );
        final manifest = json.decode(raw) as Map<String, dynamic>;

        for (final key in _requiredManifestKeys) {
          expect(
            manifest.containsKey(key),
            isTrue,
            reason:
                'bundled interaction manifest is missing required key: $key',
          );
        }

        // Sanity: checksum is 64 hex chars (raw sha256, no "sha256:" prefix).
        final checksum = manifest['checksum_sha256'] as String;
        expect(
          RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum),
          isTrue,
          reason:
              'checksum_sha256 in bundled interaction manifest is not a '
              '64-char hex string: "$checksum"',
        );
      },
    );

    test(
      'openInteractionDatabase materializes the bundle and opens it in '
      'under ${_maxBootMaterializeMs}ms — boot budget guard',
      () async {
        // Use a fresh temp dir so the test always exercises the cold
        // path (writeAsBytes), not the cached path. This is the worst
        // case the boot budget needs to cover.
        final tmpDir = await Directory.systemTemp.createTemp('rg-idb-boot');
        addTearDown(() => tmpDir.delete(recursive: true));

        final stopwatch = Stopwatch()..start();
        final db = await openInteractionDatabase(
          documentsDirectory: tmpDir,
        );
        stopwatch.stop();

        try {
          expect(
            stopwatch.elapsedMilliseconds,
            lessThan(_maxBootMaterializeMs),
            reason:
                'Bundle materialize + open took '
                '${stopwatch.elapsedMilliseconds}ms, budget is '
                '${_maxBootMaterializeMs}ms. The asset got bigger or the '
                'native open path regressed — investigate before bumping '
                'the budget.',
          );

          // Confirm the materialized file is on disk where the helper
          // promised it would be — guards against a future refactor that
          // accidentally leaks an in-memory DB.
          final materialized = File(
            p.join(tmpDir.path, 'interaction_db.sqlite'),
          );
          expect(await materialized.exists(), isTrue);
          expect(
            await materialized.length(),
            greaterThan(_minBundledInteractionDbBytes),
          );
        } finally {
          await db.close();
        }
      },
    );

    test(
      'embedded interaction_db_metadata agrees with the bundled JSON manifest',
      () async {
        final tmpDir = await Directory.systemTemp.createTemp('rg-idb-meta');
        addTearDown(() => tmpDir.delete(recursive: true));

        final db = await openInteractionDatabase(
          documentsDirectory: tmpDir,
        );

        try {
          final rawJson = await rootBundle.loadString(
            'assets/db/interaction_db_manifest.json',
          );
          final manifest = json.decode(rawJson) as Map<String, dynamic>;

          final InteractionDbMetadata meta = await db.getMetadata();

          expect(
            meta.schemaVersion,
            equals(manifest['schema_version']),
            reason:
                'schema_version disagrees between bundled JSON manifest '
                '(${manifest['schema_version']}) and embedded SQLite '
                'interaction_db_metadata (${meta.schemaVersion})',
          );

          // total_interactions can be either int or string in JSON — the
          // pipeline writes int, manifest is JSON-parsed back to int.
          expect(
            meta.totalInteractions,
            equals(manifest['total_interactions']),
            reason:
                'total_interactions disagrees between bundled JSON manifest '
                '(${manifest['total_interactions']}) and embedded SQLite '
                'interaction_db_metadata (${meta.totalInteractions})',
          );

          // The bundle must contain at least one live (non-tombstoned)
          // row. Zero would mean every curated draft was tombstoned —
          // the import gate (I6) requires at least 1 too, but we
          // re-assert here so this gate is self-contained.
          final liveCount = await db.countLiveInteractions();
          expect(
            liveCount,
            greaterThan(0),
            reason:
                'countLiveInteractions returned 0 — no usable rows in '
                'the bundled interaction DB',
          );
        } finally {
          await db.close();
        }
      },
    );
  });
}
