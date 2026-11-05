// What a download leaves behind. A file that failed its hash is gone, and a
// partial survives for Range-resume.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'release_fixtures.dart';

const _version = '2026.11.03.120000';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.respond);

  final http.StreamedResponse Function(http.BaseRequest request) respond;
  final List<String?> ranges = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // These tests are about the plain file, so no catalog has a compressed form.
    if (request.url.path.endsWith('.gz.json')) {
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    ranges.add(request.headers['range']);
    return respond(request);
  }
}

void main() {
  late Directory workspace;
  late Directory downloads;
  late List<int> catalogBytes;
  late String catalogSha;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'test',
    );
  });

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('sync-staging');
    downloads = Directory(p.join(workspace.path, 'staging'))..createSync();
    final source = p.join(workspace.path, 'source.db');
    await buildCatalog(source, version: _version);
    catalogBytes = File(source).readAsBytesSync();
    catalogSha = sha256.convert(catalogBytes).toString();
  });

  tearDown(() => workspace.delete(recursive: true));

  http.StreamedResponse whole(List<int> bytes) => http.StreamedResponse(
    Stream.value(bytes),
    200,
    contentLength: bytes.length,
  );

  File staging() => File(p.join(downloads.path, 'catalog.staging'));

  test('a file with the right hash stages, and leaves no marker', () async {
    final svc = SyncService(
      appVersion: '1.0.0',
      httpClientFactory: () => _FakeHttpClient((_) => whole(catalogBytes)),
    );
    final file = await svc.stageCatalog(
      downloads: downloads,
      version: _version,
      expectedSha256: catalogSha,
    );
    expect(file.path, staging().path);
    expect(File('${staging().path}.version').existsSync(), isFalse);
  });

  test(
    'a file with the wrong hash is deleted before anything opens it',
    () async {
      final svc = SyncService(
        appVersion: '1.0.0',
        httpClientFactory: () => _FakeHttpClient((_) => whole(catalogBytes)),
      );
      await expectLater(
        svc.stageCatalog(
          downloads: downloads,
          version: _version,
          expectedSha256: 'f' * 64,
        ),
        throwsA(isA<StateError>()),
      );
      expect(staging().existsSync(), isFalse);
      expect(File('${staging().path}.version').existsSync(), isFalse);
    },
  );

  test('rules with the wrong hash are deleted too', () async {
    final svc = SyncService(
      appVersion: '1.0.0',
      httpClientFactory: () => _FakeHttpClient((_) => whole(catalogBytes)),
    );
    await expectLater(
      svc.stageRules(
        downloads: downloads,
        version: '1.0.16',
        storagePath: 'rules/1.0.16/interaction_db.sqlite',
        expectedSha256: 'f' * 64,
      ),
      throwsA(isA<StateError>()),
    );
    expect(File(p.join(downloads.path, 'rules.staging')).existsSync(), isFalse);
  });

  test('rules stage, close and pass their version check', () async {
    final source = p.join(workspace.path, 'rules.sqlite');
    await buildRules(source, version: '1.0.16');
    final bytes = File(source).readAsBytesSync();
    final svc = SyncService(
      appVersion: '1.0.0',
      httpClientFactory: () => _FakeHttpClient((_) => whole(bytes)),
    );
    final file = await svc.stageRules(
      downloads: downloads,
      version: '1.0.16',
      storagePath: 'rules/1.0.16/interaction_db.sqlite',
      expectedSha256: sha256.convert(bytes).toString(),
    );
    expect(file.existsSync(), isTrue);

    await expectLater(
      svc.stageRules(
        downloads: downloads,
        version: '1.0.17',
        storagePath: 'rules/1.0.17/interaction_db.sqlite',
        expectedSha256: sha256.convert(bytes).toString(),
      ),
      throwsA(isA<StateError>()),
      reason: 'the file says 1.0.16 while the manifest named 1.0.17',
    );
    expect(file.existsSync(), isFalse);
  });

  test(
    'a catalog whose version disagrees with its release is deleted',
    () async {
      final svc = SyncService(
        appVersion: '1.0.0',
        httpClientFactory: () => _FakeHttpClient((_) => whole(catalogBytes)),
      );
      await expectLater(
        svc.stageCatalog(
          downloads: downloads,
          version: '2026.12.12.000000',
          expectedSha256: catalogSha,
        ),
        throwsA(isA<StateError>()),
      );
      expect(staging().existsSync(), isFalse);
    },
  );

  test('a dropped download keeps its partial, and the next attempt resumes '
      'with Range and finishes the same file', () async {
    final half = catalogBytes.length ~/ 2;
    var dropping = true;
    final client = _FakeHttpClient((request) {
      if (dropping) {
        final body = StreamController<List<int>>();
        body.add(catalogBytes.sublist(0, half));
        body.addError(const SocketException('connection lost'));
        unawaited(body.close());
        return http.StreamedResponse(body.stream, 200);
      }
      return http.StreamedResponse(
        Stream.value(catalogBytes.sublist(half)),
        206,
        headers: {
          'content-range':
              'bytes $half-${catalogBytes.length - 1}/${catalogBytes.length}',
        },
      );
    });
    final svc = SyncService(
      appVersion: '1.0.0',
      httpClientFactory: () => client,
    );

    await expectLater(
      svc.stageCatalog(
        downloads: downloads,
        version: _version,
        expectedSha256: catalogSha,
      ),
      throwsA(anything),
    );
    expect(staging().lengthSync(), half);

    dropping = false;
    client.ranges.clear();
    await svc.stageCatalog(
      downloads: downloads,
      version: _version,
      expectedSha256: catalogSha,
    );
    expect(client.ranges.first, 'bytes=$half-');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a validated file left by a process that died before activating is '
      'not resumed into', () async {
    final client = _FakeHttpClient((_) => whole(catalogBytes));
    final svc = SyncService(
      appVersion: '1.0.0',
      httpClientFactory: () => client,
    );
    await svc.stageCatalog(
      downloads: downloads,
      version: _version,
      expectedSha256: catalogSha,
    );

    client.ranges.clear();
    await svc.stageCatalog(
      downloads: downloads,
      version: _version,
      expectedSha256: catalogSha,
    );
    expect(client.ranges.single, isNull);
  });

  http.StreamedResponse rangeNotSatisfiable(int total) => http.StreamedResponse(
    const Stream.empty(),
    416,
    headers: {'content-range': 'bytes */$total'},
  );

  test('a whole file left by a kill just before its hash check is checked, '
      'not stuck asking for bytes past its end', () async {
    staging().writeAsBytesSync(catalogBytes);
    File('${staging().path}.version').writeAsStringSync(_version);
    final client = _FakeHttpClient(
      (_) => rangeNotSatisfiable(catalogBytes.length),
    );
    final svc = SyncService(
      appVersion: '1.0.0',
      httpClientFactory: () => client,
    );
    final file = await svc.stageCatalog(
      downloads: downloads,
      version: _version,
      expectedSha256: catalogSha,
    );
    expect(file.path, staging().path);
    expect(client.ranges, ['bytes=${catalogBytes.length}-']);
  });

  test(
    'a partial longer than the object is dropped and downloaded again',
    () async {
      staging().writeAsBytesSync([...catalogBytes, 1, 2, 3]);
      File('${staging().path}.version').writeAsStringSync(_version);
      final client = _FakeHttpClient(
        (request) => request.headers['range'] == null
            ? whole(catalogBytes)
            : rangeNotSatisfiable(catalogBytes.length),
      );
      final svc = SyncService(
        appVersion: '1.0.0',
        httpClientFactory: () => client,
      );
      await svc.stageCatalog(
        downloads: downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      expect(client.ranges.last, isNull);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
