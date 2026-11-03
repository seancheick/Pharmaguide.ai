// Real catalog and rules files for the release tests. They go through the real
// database classes, because a no-op activator hides the bugs that matter here.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

const kFixtureProduct = 'dsld-1';
const kFixtureCanonicalId = 'umls:c0000001';

File? _catalogTemplate;

/// The real table shape, from the real schema. Built once per test process.
Future<File> _emptyCatalog() async {
  final existing = _catalogTemplate;
  if (existing != null) return existing;
  final folder = await Directory.systemTemp.createTemp('catalog-template');
  final file = File(p.join(folder.path, 'template.db'));
  final db = CoreDatabase(file);
  await db.customSelect('SELECT 1').get();
  await db.close();
  return _catalogTemplate = file;
}

/// A catalog with one scored product, as the pipeline would publish it. Like
/// the real one it has no drift schema version until the app prepares it.
Future<void> buildCatalog(
  String path, {
  required String version,
  String schemaVersion = '2.5.0',
  String minAppVersion = '1.0.0',
  String blobSha = 'blob-sha',
  double score = 88,
  bool empty = false,
}) async {
  (await _emptyCatalog()).copySync(path);
  final db = raw.sqlite3.open(path);
  try {
    final values = <String, Object?>{
      'dsld_id': kFixtureProduct,
      'product_name': 'Fixture Product',
      'quality_score_v4_100': score,
      'quality_score_status': 'scored',
      'quality_tier': 'Good',
      'quality_assessment_status': 'complete',
      'product_safety_status': 'caution',
      'mapped_coverage': 0.9,
      'detail_blob_sha256': blobSha,
      'exported_at': '2026-11-01T00:00:00Z',
      'export_version': '2.5.0',
    };
    for (final column in db.select('PRAGMA table_info(products_core)')) {
      final name = column['name'] as String;
      if (values.containsKey(name)) continue;
      if (column['notnull'] == 1 && column['dflt_value'] == null) {
        values[name] = '${column['type']}'.startsWith('TEXT') ? '' : 0;
      }
    }
    if (!empty) {
      db.execute(
        'INSERT INTO products_core (${values.keys.join(', ')}) '
        'VALUES (${List.filled(values.length, '?').join(', ')})',
        values.values.toList(),
      );
    }
    db.execute(
      'CREATE TABLE export_manifest (key TEXT PRIMARY KEY, value TEXT)',
    );
    for (final entry in {
      'db_version': version,
      'min_app_version': minAppVersion,
      'schema_version': schemaVersion,
    }.entries) {
      db.execute('INSERT INTO export_manifest VALUES (?, ?)', [
        entry.key,
        entry.value,
      ]);
    }
    db.execute('PRAGMA user_version = 0');
  } finally {
    db.close();
  }
}

/// Rules with a single interaction whose severity is the thing a correction
/// changes.
Future<void> buildRules(
  String path, {
  required String version,
  String severity = 'caution',
  String schemaVersion = '4.0.0',
  String minAppVersion = '1.0.0',
}) async {
  final db = InteractionDatabase(File(path));
  try {
    for (final entry in {
      'schema_version': schemaVersion,
      'built_at': '2026-11-01T00:00:00Z',
      'source_drafts_count': '1',
      'source_suppai_count': '0',
      'total_interactions': '1',
      'override_count': '0',
      'resolved_conflict_count': '0',
      'interaction_db_version': version,
      'pipeline_version': '3.4.0',
      'min_app_version': minAppVersion,
      'profile_warning_rules_count': '0',
      'profile_warning_rules_version': '6.3.0',
    }.entries) {
      await db.customStatement(
        'INSERT INTO interaction_db_metadata (key, value) VALUES (?, ?)',
        [entry.key, entry.value],
      );
    }
    await db.customStatement(
      "INSERT INTO interactions (id, agent1_type, agent1_name, agent1_id, "
      "agent1_canonical_id, agent2_type, agent2_name, agent2_id, "
      "agent2_canonical_id, severity, effect_type, mechanism, management, "
      "evidence_level, source_urls_json, source_pmids_json, type_authored, "
      "source, provenance, version_added, version_last_modified, last_updated) "
      "VALUES ('r1', 'drug', 'Warfarin', "
      "'d1', 'rxcui:11289', 'supplement', 'Fixture', 's1', "
      "'$kFixtureCanonicalId', ?, 'unknown', 'm', 'g', 'established', '[]', "
      "'[]', 'drug-supplement', 'curated', 'nih_ods', '1.0.0', '1.0.0', '2026-11-01')",
      [severity],
    );
  } finally {
    await db.close();
  }
}

Future<String> severityIn(InteractionDatabase? db) async {
  final rows = await db!
      .customSelect(
        'SELECT severity FROM interactions WHERE agent2_canonical_id = ?',
        variables: [Variable.withString(kFixtureCanonicalId)],
      )
      .get();
  return rows.single.read<String>('severity');
}

/// A bundle holding [catalog] and [rules], with the manifests a real build has.
class FakeReleaseBundle extends CachingAssetBundle {
  FakeReleaseBundle({
    required this.catalog,
    required this.rules,
    required this.catalogVersion,
    required this.rulesVersion,
  });

  final Uint8List? catalog;
  final Uint8List? rules;
  final String catalogVersion;
  final String rulesVersion;

  /// How many times a database asset was read, which a launch with nothing
  /// new should never do.
  int databaseLoads = 0;

  static Future<FakeReleaseBundle> build(
    Directory workspace, {
    required String catalogVersion,
    required String rulesVersion,
    String severity = 'caution',
  }) async {
    final catalogPath = p.join(
      workspace.path,
      'bundle-$catalogVersion-$rulesVersion.db',
    );
    final rulesPath = p.join(
      workspace.path,
      'bundle-$catalogVersion-$rulesVersion.sqlite',
    );
    await buildCatalog(catalogPath, version: catalogVersion);
    await buildRules(rulesPath, version: rulesVersion, severity: severity);
    return FakeReleaseBundle(
      catalog: await File(catalogPath).readAsBytes(),
      rules: await File(rulesPath).readAsBytes(),
      catalogVersion: catalogVersion,
      rulesVersion: rulesVersion,
    );
  }

  @override
  Future<ByteData> load(String key) async {
    databaseLoads++;
    final Uint8List? bytes = switch (key) {
      bundledCoreDatabaseAssetPath => catalog,
      bundledInteractionDatabaseAssetPath => rules,
      _ => null,
    };
    if (bytes == null) throw FlutterError('No fixture for $key');
    return ByteData.sublistView(bytes);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    return switch (key) {
      bundledCoreDatabaseManifestAssetPath => jsonEncode({
        'db_version': catalogVersion,
        if (catalog case final bytes?)
          'checksum_sha256': sha256.convert(bytes).toString(),
      }),
      bundledInteractionDatabaseManifestAssetPath => jsonEncode({
        'interaction_db_version': rulesVersion,
        if (rules case final bytes?)
          'checksum_sha256': sha256.convert(bytes).toString(),
      }),
      _ => throw FlutterError('No fixture for $key'),
    };
  }
}

/// Signs manifests the way scripts/release_manifest.py does: Ed25519 over the
/// exact canonical text, with `<key id>:<base64>` as the signature.
class ReleaseSigner {
  ReleaseSigner._(this.keyId, this._keyPair, this.publicKeyHex);

  final String keyId;
  final SimpleKeyPair _keyPair;
  final String publicKeyHex;

  Map<String, String> get keys => {keyId: publicKeyHex};

  static Future<ReleaseSigner> create({String keyId = 'test-1'}) async {
    final keyPair = await Ed25519().newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final hex = publicKey.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return ReleaseSigner._(keyId, keyPair, hex);
  }

  Future<String> sign(String signedRelease) async {
    final signature = await Ed25519().sign(
      utf8.encode(signedRelease),
      keyPair: _keyPair,
    );
    return '$keyId:${base64.encode(signature.bytes)}';
  }

  /// Canonical manifest text: sorted keys, no whitespace.
  String manifestText({
    required int sequence,
    required String catalogVersion,
    required String catalogSha256,
    String catalogSchema = '2.5.0',
    String catalogMinApp = '1.0.0',
    String? rulesVersion,
    String? rulesSha256,
    String rulesSchema = '4.0.0',
    String rulesMinApp = '1.0.0',
    String minRulesVersion = '1.0.0',
    List<String> blockedCatalog = const [],
    List<String> blockedRules = const [],
  }) {
    final rules = rulesVersion == null
        ? null
        : {
            'min_app_version': rulesMinApp,
            'path': 'rules/$rulesVersion/interaction_db.sqlite',
            'schema_version': rulesSchema,
            'sha256': rulesSha256,
            'version': rulesVersion,
          };
    return jsonEncode({
      'blocked_versions': {'catalog': blockedCatalog, 'rules': blockedRules},
      'catalog': {
        'min_app_version': catalogMinApp,
        'path': 'v$catalogVersion/pharmaguide_core.db',
        'schema_version': catalogSchema,
        'sha256': catalogSha256,
        'version': catalogVersion,
      },
      'format': 1,
      'key_id': keyId,
      'min_rules_version': minRulesVersion,
      'release_sequence': sequence,
      'rules': rules,
    });
  }
}
