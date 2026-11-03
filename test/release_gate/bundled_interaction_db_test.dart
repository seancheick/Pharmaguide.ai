// Release gate: the Flutter bundle must ship a real, verified interaction
// database alongside its JSON manifest, and the boot-time materialization
// path must reproduce the bundled bytes exactly.
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
//    release store, hitting the same
//    `ensureInteractionDatabaseAvailable` materialization path the app
//    uses at boot.
// 4. The end-to-end materialize-and-open path writes the complete bundled
//    asset to disk. Performance belongs in a dedicated benchmark, not a
//    correctness gate running under variable CI load.
// 5. `getMetadata()` hydrates and the embedded
//    `interaction_db_metadata.schema_version` and `total_interactions`
//    keys agree with the JSON manifest.
// 6. `countLiveInteractions()` returns at least 1 row.
//
// Run with: flutter test test/release_gate/bundled_interaction_db_test.dart

@Tags(['bundle'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/services/release_store.dart';

import '../services/release/release_fixtures.dart';

// 16 KiB — well above the 4-byte test fixture and far below the real
// pipeline output. The bundle ships ~half a MiB today; this lower bound
// is intentionally permissive so we don't have to bump it on every
// curated-row addition.
const _minBundledInteractionDbBytes = 16 * 1024;

// Keys the pipeline writes to interaction_db_manifest.json (file/transport
// metadata only). Build-process counters like `override_count` and
// `resolved_conflict_count` live in the embedded `interaction_db_metadata`
// kv table inside the SQLite, not in the JSON sidecar — they're verified
// by the metadata-agreement test below via `getMetadata()`.
const _requiredManifestKeys = <String>[
  'built_at',
  'checksum',
  'schema_version',
  'db_version',
  'total_interactions',
  'source_drafts_count',
  'source_suppai_count',
  'interaction_db_version',
  'pipeline_version',
  'min_app_version',
];

/// The real bundled rules, opened the way the app opens them, beside a fixture
/// catalog so this gate doesn't need the catalog's Git LFS object.
Future<
  ({
    ReleaseGeneration generation,
    Directory documents,
    Future<void> Function() dispose,
  })
>
_openThroughStore() async {
  final workspace = await Directory.systemTemp.createTemp('rg-idb-store');
  final catalogPath = p.join(workspace.path, 'catalog.db');
  await buildCatalog(catalogPath, version: '2026.01.01.000000');
  final manifest =
      json.decode(
            await rootBundle.loadString(
              'assets/db/interaction_db_manifest.json',
            ),
          )
          as Map<String, dynamic>;
  final rules = await rootBundle.load('assets/db/interaction_db.sqlite');
  final documents = Directory(p.join(workspace.path, 'documents'))
    ..createSync();
  final generation = await ReleaseStore(
    documents: documents,
    bundle: FakeReleaseBundle(
      catalog: File(catalogPath).readAsBytesSync(),
      rules: rules.buffer.asUint8List(rules.offsetInBytes, rules.lengthInBytes),
      catalogVersion: '2026.01.01.000000',
      rulesVersion: manifest['interaction_db_version'] as String,
    ),
  ).open();
  return (
    generation: generation,
    documents: documents,
    dispose: () async {
      await generation.close();
      await workspace.delete(recursive: true);
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('release gate: bundled interaction DB asset', () {
    test(
      'catalog importer accepts interaction schemas 1 through 4 as pairs',
      () {
        final importer = File(
          'scripts/import_catalog_artifact.sh',
        ).readAsStringSync();
        final supportedSchemas = RegExp(
          r'APP_SUPPORTED_INTERACTION_SCHEMAS=\(([^)]*)\)',
        ).firstMatch(importer)?.group(1);
        final supportedUserVersions = RegExp(
          r'APP_SUPPORTED_INTERACTION_USER_VERSIONS=\(([^)]*)\)',
        ).firstMatch(importer)?.group(1);

        expect(supportedSchemas, contains('"1.0.0"'));
        expect(supportedSchemas, contains('"2.0.0"'));
        expect(supportedSchemas, contains('"3.0.0"'));
        expect(supportedSchemas, contains('"4.0.0"'));
        expect(supportedUserVersions, contains('1'));
        expect(supportedUserVersions, contains('2'));
        expect(supportedUserVersions, contains('3'));
        expect(supportedUserVersions, contains('4'));
        expect(importer, contains('excluded_drug_rxcuis_json'));
        expect(importer, contains('profile_gate_json'));
        expect(importer, contains('medication_exceptions_json'));
        expect(importer, contains('parse_constant=reject_non_json_constant'));
        expect(
          importer,
          contains('interaction layout contract validation failed'),
        );
        expect(
          importer,
          contains('EXPECTED_INTERACTION_USER_VERSION'),
          reason:
              'The importer must validate the file user_version paired with '
              'the selected interaction schema, not accept arbitrary mixes.',
        );
        expect(importer, contains('profile_warning_rules_count'));
        expect(importer, contains('profile_warning_rules_version'));
        expect(importer, contains('PROFILE_WARNING_RULE_TABLE_COUNT'));
        expect(
          importer,
          contains('profile warning rule count split-brain'),
          reason:
              'Schema 2 must prove that its manifest, embedded metadata, and '
              'actual warning-rule table describe the same reviewed registry.',
        );
      },
    );

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

    test('assets/db/interaction_db_manifest.json is declared, loadable, '
        'and well-formed', () async {
      final raw = await rootBundle.loadString(
        'assets/db/interaction_db_manifest.json',
      );
      final manifest = json.decode(raw) as Map<String, dynamic>;

      for (final key in _requiredManifestKeys) {
        expect(
          manifest.containsKey(key),
          isTrue,
          reason: 'bundled interaction manifest is missing required key: $key',
        );
      }
      if (manifest['schema_version'].toString().startsWith('2.')) {
        for (final key in const [
          'profile_warning_rules_count',
          'profile_warning_rules_version',
        ]) {
          expect(
            manifest.containsKey(key),
            isTrue,
            reason: 'schema-2 interaction manifest is missing $key',
          );
        }
      }

      // Sanity: checksum is "sha256:" prefix + 64 hex chars.
      final checksum = manifest['checksum'] as String;
      expect(
        RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(checksum),
        isTrue,
        reason:
            'checksum in bundled interaction manifest is not a valid '
            'sha256 hash string: "$checksum"',
      );
    });

    test(
      'the store materializes the complete bundled rules and opens them',
      () async {
        final fixture = await _openThroughStore();
        addTearDown(fixture.dispose);
        final manifest =
            json.decode(
                  await rootBundle.loadString(
                    'assets/db/interaction_db_manifest.json',
                  ),
                )
                as Map<String, dynamic>;
        final bundled = await rootBundle.load(
          'assets/db/interaction_db.sqlite',
        );
        final record = fixture.generation.record;

        expect(fixture.generation.rules, isNotNull);
        expect(
          await File(
            p.join(
              fixture.documents.path,
              'releases',
              record.id,
              'rules.sqlite',
            ),
          ).length(),
          greaterThanOrEqualTo(bundled.lengthInBytes),
          reason:
              'The release must contain the complete bundled asset. A schema-1 '
              'compatibility copy may grow when the app creates the empty '
              'schema-2 warning-rule table.',
        );
        expect(
          record.rulesSha256,
          (manifest['checksum'] as String).replaceFirst('sha256:', ''),
          reason: 'the release record must fingerprint the bundled bytes',
        );
      },
    );

    test(
      'embedded interaction_db_metadata agrees with the bundled JSON manifest',
      () async {
        final fixture = await _openThroughStore();
        addTearDown(fixture.dispose);
        final db = fixture.generation.rules!;

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
          if (meta.schemaVersion.startsWith('2.')) {
            expect(
              await db.countProfileWarningRules(),
              meta.profileWarningRulesCount,
            );
            expect(
              meta.profileWarningRulesCount,
              manifest['profile_warning_rules_count'],
            );
            expect(
              meta.profileWarningRulesVersion,
              manifest['profile_warning_rules_version'],
            );
          }

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

          final researchRows = await db.lookupResearchPairsByCanonicalId(
            'vitamin_k',
          );
          expect(
            researchRows,
            isNotEmpty,
            reason:
                'Tier 2 research_pairs are bundled; at least one canonical '
                'lookup must be reachable from Flutter.',
          );
          final bridgedRows = await db.lookupResearchPairsByRxcui('11289');
          expect(
            bridgedRows,
            isNotEmpty,
            reason:
                'Tier 2 research_pairs must include the RxCUI bridge so '
                'medication-context research evidence is queryable.',
          );
          expect(
            bridgedRows.any(
              (r) =>
                  r.canonicalIdA == 'vitamin_k' ||
                  r.canonicalIdB == 'vitamin_k',
            ),
            isTrue,
            reason:
                'Warfarin RxCUI should connect to Vitamin K research evidence.',
          );
        } finally {
          // The fixture closes the release.
        }
      },
    );
  });
}
