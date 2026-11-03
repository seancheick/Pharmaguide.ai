// A release from the publisher's row to the rules a check reads, over real HTTP:
// PostgREST and Storage paths on a local server, the real SyncService, updater
// and store, and real SQLite files. A new store over the same folder is a
// restart. `_tick` is the update step lib/main.dart runs.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/services/catalog_updater_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/release_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'release_fixtures.dart';

const _bundledCatalog = '2026.01.01.000000';
const _bundledRules = '1.0.15';
const _appVersion = '1.0.0';

/// What a publisher controls: the current manifest row and the storage files.
class _FakePublisher {
  late HttpServer server;
  Map<String, Object?>? row;
  final Map<String, Uint8List> files = {};
  final List<String> downloads = [];
  bool down = false;
  bool signedColumnsMissing = false;
  String? manifestSelect;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      final response = request.response;
      if (down) {
        response.statusCode = 503;
      } else if (path == '/rest/v1/export_manifest' &&
          signedColumnsMissing &&
          request.uri.queryParameters['select']!.contains('signed_release')) {
        // What PostgREST 14.5 answers before the release migration is applied.
        response.statusCode = 400;
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({
            'code': '42703',
            'details': null,
            'hint': null,
            'message': 'column export_manifest.signed_release does not exist',
          }),
        );
      } else if (path == '/rest/v1/export_manifest') {
        manifestSelect = request.uri.queryParameters['select'];
        final wantsObject = request.headers
            .value('accept')
            ?.contains('vnd.pgrst.object');
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode(wantsObject == true ? row : [if (row != null) row]),
        );
      } else if (path.startsWith('/storage/v1/object/public/pharmaguide/')) {
        final key = path.substring(
          '/storage/v1/object/public/pharmaguide/'.length,
        );
        final bytes = files[key];
        if (bytes == null) {
          response.statusCode = 404;
        } else {
          downloads.add(key);
          response.contentLength = bytes.length;
          response.add(bytes);
        }
      } else {
        response.statusCode = 503;
      }
      await response.close();
    });
  }
}

void main() {
  late _FakePublisher publisher;
  late ReleaseSigner signer;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await CrashReportingService().initialize();
    publisher = _FakePublisher();
    await publisher.start();
    await Supabase.initialize(
      url: 'http://127.0.0.1:${publisher.server.port}',
      publishableKey: 'fixture-only',
      debug: false,
    );
    signer = await ReleaseSigner.create();
  });

  tearDownAll(() => publisher.server.close(force: true));

  late Directory workspace;
  late Directory documents;
  late FakeReleaseBundle bundle;
  final open = <ReleaseGeneration>[];

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('release-e2e');
    documents = Directory(p.join(workspace.path, 'documents'))..createSync();
    bundle = await FakeReleaseBundle.build(
      workspace,
      catalogVersion: _bundledCatalog,
      rulesVersion: _bundledRules,
    );
    publisher
      ..row = null
      ..files.clear()
      ..downloads.clear()
      ..down = false;
  });

  tearDown(() async {
    for (final generation in open) {
      await generation.close();
    }
    open.clear();
    await workspace.delete(recursive: true);
  });

  Future<({ReleaseStore store, ReleaseGeneration generation})> launch() async {
    final store = ReleaseStore(documents: documents, bundle: bundle);
    final generation = await store.open();
    open.add(generation);
    return (store: store, generation: generation);
  }

  CatalogUpdaterService updaterFor(
    ReleaseStore store, {
    Map<String, String>? keys,
  }) {
    final sync = SyncService(appVersion: _appVersion);
    return CatalogUpdaterService(
      probeRemoteRelease: sync.fetchCurrentRelease,
      appVersion: _appVersion,
      verificationKeys: keys ?? signer.keys,
      stageCatalog: ({required version, storagePath, expectedSha256}) =>
          sync.stageCatalog(
            downloads: store.downloads,
            version: version,
            storagePath: storagePath,
            expectedSha256: expectedSha256,
          ),
      stageRules:
          ({required version, required storagePath, required expectedSha256}) =>
              sync.stageRules(
                downloads: store.downloads,
                version: version,
                storagePath: storagePath,
                expectedSha256: expectedSha256,
              ),
    );
  }

  /// One refresh tick from lib/main.dart, without its fleet jitter.
  Future<ReleaseGeneration> tick(
    ReleaseStore store,
    ReleaseGeneration current, {
    Map<String, String>? keys,
  }) async {
    final updater = updaterFor(store, keys: keys);
    final installed = InstalledRelease.of(store);
    final check = await updater.checkForUpdate(
      installed: installed,
      onVerified: (manifest) => store.recordVerified(
        sequence: manifest.sequence,
        blockedCatalog: manifest.blockedCatalog,
        blockedRules: manifest.blockedRules,
      ),
    );
    var generation = current;
    if (check is CatalogUpdateFound) {
      final staged = await updater.stage(check, installed: installed);
      if (staged is CatalogStaged) {
        final result = await store.activate(staged.candidate);
        if (result is ReleaseActivated) {
          generation = result.generation;
          open.add(generation);
        }
      }
    }
    if (!store.isSettled(generation)) {
      generation = await store.reselect();
      open.add(generation);
    }
    return generation;
  }

  String sha(Uint8List bytes) => sha256.convert(bytes).toString();

  Future<Uint8List> rulesFile(String version, String severity) async {
    final path = p.join(workspace.path, 'published-$version-$severity.sqlite');
    await buildRules(path, version: version, severity: severity);
    return File(path).readAsBytesSync();
  }

  Future<Uint8List> catalogFile(String version) async {
    final path = p.join(workspace.path, 'published-$version.db');
    await buildCatalog(path, version: version);
    return File(path).readAsBytesSync();
  }

  /// Publishes a signed row the way scripts/release_manifest.py and
  /// sync_to_supabase.py do.
  Future<void> publish({
    required int sequence,
    required String catalogVersion,
    required Uint8List catalog,
    String? rulesVersion,
    Uint8List? rules,
    String minRulesVersion = '1.0.0',
    List<String> blockedCatalog = const [],
    List<String> blockedRules = const [],
  }) async {
    publisher.files['v$catalogVersion/pharmaguide_core.db'] = catalog;
    if (rules != null) {
      publisher.files['rules/$rulesVersion/interaction_db.sqlite'] = rules;
    }
    final text = signer.manifestText(
      sequence: sequence,
      catalogVersion: catalogVersion,
      catalogSha256: sha(catalog),
      rulesVersion: rulesVersion,
      rulesSha256: rules == null ? null : sha(rules),
      minRulesVersion: minRulesVersion,
      blockedCatalog: blockedCatalog,
      blockedRules: blockedRules,
    );
    publisher.row = {
      'db_version': catalogVersion,
      'checksum': 'sha256:${sha(catalog)}',
      'is_current': true,
      'release_sequence': sequence,
      'signed_release': text,
      'release_signature': await signer.sign(text),
    };
  }

  test('a changed rule reaches the phone with no app update, downloads only '
      'the rules, and survives a restart', () async {
    final first = await launch();
    expect(await severityIn(first.generation.rules), 'caution');

    await publish(
      sequence: 1,
      catalogVersion: _bundledCatalog,
      catalog: bundle.catalog!,
      rulesVersion: '1.0.16',
      rules: await rulesFile('1.0.16', 'contraindicated'),
    );
    final updated = await tick(first.store, first.generation);

    expect(await severityIn(updated.rules), 'contraindicated');
    expect(publisher.downloads, ['rules/1.0.16/interaction_db.sqlite']);
    expect(
      await severityIn(first.generation.rules),
      'caution',
      reason: 'a check already running finishes on its own release',
    );

    final restarted = await launch();
    expect(restarted.generation.record.rulesVersion, '1.0.16');
    expect(await severityIn(restarted.generation.rules), 'contraindicated');
  });

  test('a result does not change because the phone went offline or time '
      'passed', () async {
    final first = await launch();
    await publish(
      sequence: 1,
      catalogVersion: _bundledCatalog,
      catalog: bundle.catalog!,
      rulesVersion: '1.0.16',
      rules: await rulesFile('1.0.16', 'avoid'),
    );
    final updated = await tick(first.store, first.generation);
    final id = updated.record.id;

    publisher.down = true;
    final again = await tick(first.store, updated);
    expect(identical(again, updated), isTrue);
    for (var launchCount = 0; launchCount < 2; launchCount++) {
      final offline = await launch();
      expect(offline.generation.record.id, id);
      expect(await severityIn(offline.generation.rules), 'avoid');
    }
  });

  test(
    'an incompatible pair never activates, and a later good one does',
    () async {
      final first = await launch();
      await publish(
        sequence: 1,
        catalogVersion: '2026.02.01.000000',
        catalog: await catalogFile('2026.02.01.000000'),
        minRulesVersion: '1.1.0',
      );
      final refused = await tick(first.store, first.generation);
      expect(refused.record.id, first.generation.record.id);
      expect(publisher.downloads, isEmpty, reason: 'decided from the manifest');

      await publish(
        sequence: 2,
        catalogVersion: '2026.02.01.000000',
        catalog: await catalogFile('2026.02.01.000000'),
        rulesVersion: '1.1.0',
        rules: await rulesFile('1.1.0', 'avoid'),
        minRulesVersion: '1.1.0',
      );
      final good = await tick(first.store, refused);
      expect(good.record.catalogVersion, '2026.02.01.000000');
      expect(good.record.rulesVersion, '1.1.0');
    },
  );

  test('a file that is not what the release signed never activates', () async {
    final first = await launch();
    await publish(
      sequence: 1,
      catalogVersion: _bundledCatalog,
      catalog: bundle.catalog!,
      rulesVersion: '1.0.16',
      rules: await rulesFile('1.0.16', 'contraindicated'),
    );
    publisher.files['rules/1.0.16/interaction_db.sqlite'] = await rulesFile(
      '1.0.16',
      'monitor',
    );
    final after = await tick(first.store, first.generation);
    expect(after.record.rulesVersion, _bundledRules);
    expect(await severityIn(after.rules), 'caution');
  });

  test('rollback works through a real restart on a phone that skipped '
      'releases, and a replay of the bad release is refused', () async {
    final first = await launch();
    final badRules = await rulesFile('1.0.20', 'monitor');
    await publish(
      sequence: 5,
      catalogVersion: _bundledCatalog,
      catalog: bundle.catalog!,
      rulesVersion: '1.0.20',
      rules: badRules,
    );
    final bad = await tick(first.store, first.generation);
    expect(await severityIn(bad.rules), 'monitor');
    final badRow = Map<String, Object?>.of(publisher.row!);

    // Sequences 6 to 8 went out while this phone was away. The correction
    // names known-good older rules and revokes the bad ones.
    await publish(
      sequence: 9,
      catalogVersion: _bundledCatalog,
      catalog: bundle.catalog!,
      rulesVersion: '1.0.18',
      rules: await rulesFile('1.0.18', 'contraindicated'),
      blockedRules: ['1.0.20'],
    );
    final restarted = await launch();
    expect(await severityIn(restarted.generation.rules), 'monitor');
    final rolledBack = await tick(restarted.store, restarted.generation);
    expect(rolledBack.record.rulesVersion, '1.0.18');
    expect(await severityIn(rolledBack.rules), 'contraindicated');

    final afterRollback = await launch();
    expect(afterRollback.generation.record.rulesVersion, '1.0.18');

    publisher.row = badRow;
    final replayed = await tick(afterRollback.store, afterRollback.generation);
    expect(replayed.record.rulesVersion, '1.0.18');
    expect(await severityIn(replayed.rules), 'contraindicated');
  });

  test('a revocation with no replacement withholds interaction checks only, '
      'and holds while offline after a restart', () async {
    final first = await launch();
    await publish(
      sequence: 3,
      catalogVersion: _bundledCatalog,
      catalog: bundle.catalog!,
      blockedRules: [_bundledRules],
      minRulesVersion: '1.0.0',
    );
    final withheld = await tick(first.store, first.generation);
    expect(withheld.rulesWithheld, isTrue);
    expect(withheld.rules, isNull);
    expect(await withheld.core.countProducts(), 1);

    publisher.down = true;
    final offline = await launch();
    expect(offline.generation.rulesWithheld, isTrue);
    expect(await offline.generation.core.countProducts(), 1);
  });

  test('the manifest read names its columns, so a column grant cannot break '
      'it', () async {
    publisher.row = {
      'db_version': '2026.02.01.000000',
      'checksum': 'sha256:abc',
      'is_current': true,
      'signed_release': '{}',
      'release_signature': 'signature',
    };

    final release = await SyncService().fetchCurrentRelease();

    expect(
      publisher.manifestSelect,
      'db_version,checksum,signed_release,release_signature',
    );
    expect(release!.signedRelease, '{}');
    expect(release.releaseSignature, 'signature');
  });

  test('a database without the release migration keeps updating the catalog, '
      'because naming the signed columns must not stop updates', () async {
    publisher.row = {
      'db_version': '2026.02.01.000000',
      'checksum': 'sha256:abc',
      'is_current': true,
    };
    publisher.signedColumnsMissing = true;
    addTearDown(() => publisher.signedColumnsMissing = false);

    final release = await SyncService().fetchCurrentRelease();

    expect(publisher.manifestSelect, 'db_version,checksum');
    expect(release!.dbVersion, '2026.02.01.000000');
    expect(release.checksum, 'sha256:abc');
    expect(release.signedRelease, isNull);
    expect(release.releaseSignature, isNull);
  });

  test('a build with no keys, like every public build today, ignores a signed '
      'row\'s rules and never activates them', () async {
    final first = await launch();
    final catalog = await catalogFile('2026.02.01.000000');
    await publish(
      sequence: 1,
      catalogVersion: '2026.02.01.000000',
      catalog: catalog,
      rulesVersion: '1.0.16',
      rules: await rulesFile('1.0.16', 'contraindicated'),
    );
    final generation = await tick(
      first.store,
      first.generation,
      keys: const {},
    );
    expect(generation.record.catalogVersion, '2026.02.01.000000');
    expect(generation.record.rulesVersion, _bundledRules);
    expect(await severityIn(generation.rules), 'caution');
    expect(publisher.downloads, ['v2026.02.01.000000/pharmaguide_core.db']);
  });
}
