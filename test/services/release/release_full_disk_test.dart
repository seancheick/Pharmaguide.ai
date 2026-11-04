// The upgrade on a phone with no room, on a volume that is really full, with the
// real bundled files. It needs a small disk image, so it runs only when one is
// given:
//
//   hdiutil create -size 110m -fs HFS+ -volname pgfull /tmp/pgfull.dmg
//   hdiutil attach /tmp/pgfull.dmg
//   PG_RELEASE_FULL_VOLUME=/Volumes/pgfull \
//     flutter test test/services/release/release_full_disk_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/release_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'release_fixtures.dart';

void main() {
  final volume = Platform.environment['PG_RELEASE_FULL_VOLUME'];

  test(
    'an install keeps working when the volume has no room for a second copy',
    () async {
      await CrashReportingService().initialize();
      final documents = Directory(p.join(volume!, 'documents'))
        ..createSync(recursive: true);
      addTearDown(() => documents.deleteSync(recursive: true));
      final catalog = File('assets/db/pharmaguide_core.db');
      final rules = File('assets/db/interaction_db.sqlite');
      catalog.copySync(p.join(documents.path, 'pharmaguide_core.db'));
      rules.copySync(p.join(documents.path, 'interaction_db.sqlite'));

      // Fill what is left, then free only enough for the small files.
      final filler = File(
        p.join(documents.path, 'filler'),
      ).openSync(mode: FileMode.write);
      final chunk = List<int>.filled(1 << 18, 0);
      var written = 0;
      try {
        while (true) {
          filler.writeFromSync(chunk);
          written += chunk.length;
        }
      } on FileSystemException {
        filler.truncateSync(written - (1 << 20));
      }
      filler.closeSync();

      final bundle = FakeReleaseBundle(
        catalog: await catalog.readAsBytes(),
        rules: await rules.readAsBytes(),
        catalogVersion:
            jsonDecode(
                  File('assets/db/export_manifest.json').readAsStringSync(),
                )['db_version']
                as String,
        rulesVersion:
            jsonDecode(
                  File(
                    'assets/db/interaction_db_manifest.json',
                  ).readAsStringSync(),
                )['interaction_db_version']
                as String,
      );

      final store = ReleaseStore(documents: documents, bundle: bundle);
      final generation = await store.open();
      addTearDown(generation.close);

      expect(generation.record.catalogVersion, bundle.catalogVersion);
      expect(generation.rules, isNotNull);
      expect(await generation.core.validateCatalogSnapshot(), isNotNull);
    },
    skip: volume == null ? 'needs PG_RELEASE_FULL_VOLUME' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'a disk that fills while a catalog decompresses leaves the last good '
    'release active, and the update lands once there is room',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://example.test',
        publishableKey: 'test',
      );
      await CrashReportingService().initialize();
      const bundledVersion = '2026.01.01.000000';
      const version = '2026.11.03.120000';
      final local = await Directory.systemTemp.createTemp('full-disk');
      addTearDown(() => local.delete(recursive: true));
      final documents = Directory(p.join(volume!, 'documents-decompress'))
        ..createSync(recursive: true);
      addTearDown(() => documents.deleteSync(recursive: true));

      final bundle = await FakeReleaseBundle.build(
        local,
        catalogVersion: bundledVersion,
        rulesVersion: '1.0.15',
      );
      final store = ReleaseStore(documents: documents, bundle: bundle);
      final generation = await store.open();
      addTearDown(generation.close);

      // A real catalog with padding, so the gz fits and what comes out of it
      // doesn't.
      final source = p.join(local.path, 'published.db');
      await buildCatalog(source, version: version);
      final padding = Uint8List(24 << 20);
      final random = Random(7);
      for (var i = 0; i < padding.length; i += 512) {
        padding[i] = random.nextInt(256);
      }
      final padded = raw.sqlite3.open(source);
      padded.execute('CREATE TABLE padding (bytes BLOB)');
      padded.execute('INSERT INTO padding VALUES (?)', [padding]);
      padded.close();
      final catalog = File(source).readAsBytesSync();
      final gz = gzip.encode(catalog);

      final fill = File(
        p.join(documents.path, 'filler'),
      ).openSync(mode: FileMode.write);
      final chunk = List<int>.filled(1 << 18, 0);
      var written = 0;
      try {
        while (true) {
          fill.writeFromSync(chunk);
          written += chunk.length;
        }
      } on FileSystemException {
        // Room for the gz and a little more, far short of the catalog.
        fill.truncateSync(written - gz.length - (4 << 20));
      }
      fill.closeSync();

      final digest = sha256.convert(catalog).toString();
      final client = _Objects({
        'v$version/pharmaguide_core.db': catalog,
        'v$version/pharmaguide_core.db.gz': gz,
      });
      final compressed = CompressedCatalog(
        path: 'v$version/pharmaguide_core.db.gz',
        sha256: sha256.convert(gz).toString(),
        size: gz.length,
        decompressedSize: catalog.length,
      );
      final service = SyncService(
        appVersion: '1.0.0',
        httpClientFactory: () => client,
        // The measurement is what this test bypasses: the write itself must fail.
        availableBytes: (_) async => null,
      );

      Object? failure;
      try {
        await service.stageCatalog(
          downloads: store.downloads,
          version: version,
          expectedSha256: digest,
          compressed: compressed,
        );
      } on Object catch (error) {
        failure = error;
      }
      expect(failure, isA<FileSystemException>());
      expect((failure! as FileSystemException).osError?.errorCode, 28);
      expect(
        File(
          p.join(store.downloads.path, 'catalog.staging.decompressing'),
        ).existsSync(),
        isFalse,
        reason: 'the room a partial took is given back straight away',
      );
      expect(
        client.requested,
        isNot(contains('v$version/pharmaguide_core.db')),
      );
      expect(store.active!.catalogVersion, bundledVersion);

      final relaunched = ReleaseStore(documents: documents, bundle: bundle);
      final kept = await relaunched.open();
      addTearDown(kept.close);
      expect(kept.record.catalogVersion, bundledVersion);
      expect(await kept.core.validateCatalogSnapshot(), bundledVersion);

      // Room again: no second download, and the update lands.
      File(p.join(documents.path, 'filler')).deleteSync();
      client.requested.clear();
      final staged = await service.stageCatalog(
        downloads: relaunched.downloads,
        version: version,
        expectedSha256: digest,
        compressed: compressed,
      );
      expect(client.requested, isEmpty);
      final result = await relaunched.activate(
        ReleaseCandidate(
          sequence: 0,
          catalogVersion: version,
          catalogSha256: digest,
          minRulesVersion: null,
          stagedCatalog: staged,
        ),
      );
      final activated = result as ReleaseActivated;
      addTearDown(activated.generation.close);
      expect(activated.generation.record.catalogVersion, version);
    },
    skip: volume == null ? 'needs PG_RELEASE_FULL_VOLUME' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _Objects extends http.BaseClient {
  _Objects(this.objects);

  final Map<String, List<int>> objects;
  final List<String> requested = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = request.url.path.split('/pharmaguide/').last;
    requested.add(key);
    final bytes = objects[key];
    return bytes == null
        ? http.StreamedResponse(const Stream.empty(), 400)
        : http.StreamedResponse(
            Stream.value(bytes),
            200,
            contentLength: bytes.length,
          );
  }
}
