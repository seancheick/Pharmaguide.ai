// A compressed catalog from the wire to an active release. The real SyncService,
// real gzip, real SQLite files and the real store. Whatever goes wrong on the way,
// the phone's last good release stays active.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/supabase/supabase_contract.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/services/release_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'release_fixtures.dart';

const _bundledCatalog = '2026.01.01.000000';
const _bundledRules = '1.0.15';
const _version = '2026.11.03.120000';

String _shaOf(List<int> bytes) => sha256.convert(bytes).toString();

/// Storage as a phone sees it: an object by path, Range included, or the 400 the
/// real public endpoint answers for an object that isn't there.
class _StorageClient extends http.BaseClient {
  _StorageClient(this.current);
  final _FakeStorage Function() current;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      current().send(request);
}

class _FakeStorage extends http.BaseClient {
  final Map<String, List<int>> objects = {};
  final List<String> requested = [];

  /// Paths whose body stops after this many bytes, then fails.
  final Map<String, int> dropAfter = {};
  final List<String?> ranges = [];
  final Map<String, (int, String)> failures = {};
  final Map<String, (int, String)> publicFailures = {};
  final Map<String, Object> errors = {};
  final Map<String, Completer<http.StreamedResponse>> pending = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = request.url.path.split('/pharmaguide/').last;
    requested.add(key);
    final stalled = pending[key];
    if (stalled != null) return stalled.future;
    final error = errors[key];
    if (error != null) throw error;
    final direct = publicFailures[key];
    if (direct != null && request.url.path.contains('/object/public/')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(direct.$2)),
        direct.$1,
      );
    }
    final failure = failures[key];
    if (failure != null) {
      // Denied public access exercises the real authenticated SDK fallback.
      if (request.url.path.contains('/object/public/')) {
        return http.StreamedResponse(const Stream.empty(), 403);
      }
      return http.StreamedResponse(
        Stream.value(utf8.encode(failure.$2)),
        failure.$1,
      );
    }
    final range = request.headers['range'];
    ranges.add(range);
    final bytes = objects[key];
    if (bytes == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"not_found"}')),
        400,
      );
    }
    final drop = dropAfter.remove(key);
    if (drop != null) {
      final body = StreamController<List<int>>();
      body.add(bytes.sublist(0, drop));
      body.addError(const SocketException('connection lost'));
      unawaited(body.close());
      return http.StreamedResponse(body.stream, 200);
    }
    if (range != null) {
      final start = int.parse(range.substring(6, range.length - 1));
      if (start >= bytes.length) {
        return http.StreamedResponse(
          const Stream.empty(),
          416,
          headers: {'content-range': 'bytes */${bytes.length}'},
        );
      }
      return http.StreamedResponse(
        Stream.value(bytes.sublist(start)),
        206,
        headers: {
          'content-range': 'bytes $start-${bytes.length - 1}/${bytes.length}',
        },
      );
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      contentLength: bytes.length,
    );
  }
}

void main() {
  late Directory workspace;
  late Directory documents;
  late FakeReleaseBundle bundle;
  late _FakeStorage storage;
  late List<int> catalogBytes;
  late List<int> gzBytes;
  late String catalogSha;
  final rawPath = SupabaseContract.coreDbPath(_version);
  final gzPath = SupabaseContract.compressedCoreDbPath(_version);
  final descriptorPath = SupabaseContract.compressedCoreDbDescriptorPath(
    _version,
  );
  final open = <ReleaseGeneration>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'test',
      httpClient: _StorageClient(() => storage),
    );
  });

  Map<String, Object?> descriptor({
    String? version,
    String? path,
    String? sha,
    int? size,
    String? decompressedSha,
    int? decompressedSize,
  }) => {
    'format': 1,
    'version': version ?? _version,
    'path': path ?? gzPath,
    'sha256': sha ?? _shaOf(gzBytes),
    'size': size ?? gzBytes.length,
    'decompressed_sha256': decompressedSha ?? catalogSha,
    'decompressed_size': decompressedSize ?? catalogBytes.length,
  };

  void publish({Map<String, Object?>? described, List<int>? gz}) {
    storage.objects
      ..[rawPath] = catalogBytes
      ..[gzPath] = gz ?? gzBytes
      ..[descriptorPath] = utf8.encode(jsonEncode(described ?? descriptor()));
  }

  SyncService service({int? free, int? Function()? freeNow}) => SyncService(
    appVersion: '1.0.0',
    httpClientFactory: () => storage,
    availableBytes: (_) async => freeNow != null ? freeNow() : free,
  );

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('compressed-catalog');
    documents = Directory(p.join(workspace.path, 'documents'))..createSync();
    bundle = await FakeReleaseBundle.build(
      workspace,
      catalogVersion: _bundledCatalog,
      rulesVersion: _bundledRules,
    );
    final source = p.join(workspace.path, 'source.db');
    await buildCatalog(source, version: _version);
    catalogBytes = File(source).readAsBytesSync();
    gzBytes = gzip.encode(catalogBytes);
    catalogSha = _shaOf(catalogBytes);
    storage = _FakeStorage();
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

  ReleaseCandidate candidateFrom(File staged) => ReleaseCandidate(
    sequence: 0,
    catalogVersion: _version,
    catalogSha256: catalogSha,
    minRulesVersion: null,
    stagedCatalog: staged,
  );

  Future<void> expectLastGoodActive(ReleaseStore store) async {
    expect(store.active!.catalogVersion, _bundledCatalog);
    final relaunched = await launch();
    expect(relaunched.store.active!.catalogVersion, _bundledCatalog);
    expect(
      await relaunched.generation.core.validateCatalogSnapshot(),
      _bundledCatalog,
    );
  }

  String stagingPath(ReleaseStore store, String name) =>
      p.join(store.downloads.path, name);

  group('the compressed path', () {
    test('downloads only the gz, then activates the exact catalog', () async {
      publish();
      final phone = await launch();
      final staged = await service().stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      expect(storage.requested, [descriptorPath, gzPath]);
      expect(
        File(stagingPath(phone.store, 'catalog.gz.staging')).existsSync(),
        isFalse,
      );

      final result = await phone.store.activate(candidateFrom(staged));
      final activated = result as ReleaseActivated;
      open.add(activated.generation);
      expect(activated.generation.record.catalogVersion, _version);
      expect(activated.generation.record.catalogSha256, catalogSha);
      expect(await activated.generation.core.countProducts(), 1);
    });

    test('a signed entry is used with no descriptor to read', () async {
      publish();
      final phone = await launch();
      await service().stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
        storagePath: rawPath,
        expectedSha256: catalogSha,
        compressed: CompressedCatalog(
          path: gzPath,
          sha256: _shaOf(gzBytes),
          size: gzBytes.length,
          decompressedSize: catalogBytes.length,
        ),
      );
      expect(storage.requested, [gzPath]);
    });

    test('runs off the UI isolate', () async {
      final source = File(p.join(workspace.path, 'a.gz'))
        ..writeAsBytesSync(gzBytes);
      final name = await decompressCatalogOffUiIsolate(
        source: source.path,
        target: p.join(workspace.path, 'a.db'),
        expectedSha256: catalogSha,
        expectedBytes: catalogBytes.length,
      );
      expect(name, isNot(Isolate.current.debugName));
    });

    test('the hash of the bytes as published is checked before the file is '
        'opened, because opening changes it', () async {
      final source = File(p.join(workspace.path, 'a.gz'))
        ..writeAsBytesSync(gzBytes);
      final target = File(p.join(workspace.path, 'a.db'));
      await decompressCatalogOffUiIsolate(
        source: source.path,
        target: target.path,
        expectedSha256: catalogSha,
        expectedBytes: catalogBytes.length,
      );
      expect(target.readAsBytesSync(), catalogBytes);
    });
  });

  group('older catalogs and bad descriptors use the plain file', () {
    test('no descriptor', () async {
      storage.objects[rawPath] = catalogBytes;
      final phone = await launch();
      await service().stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      expect(storage.requested, [descriptorPath, rawPath]);
    });

    test('a row with no checksum never asks for a descriptor', () async {
      storage.objects[rawPath] = catalogBytes;
      final phone = await launch();
      await service().stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
      );
      expect(storage.requested, [rawPath]);
    });

    final bad = <String, Map<String, Object?> Function(Map<String, Object?>)>{
      'another version': (d) => {...d, 'version': '2026.11.04.120000'},
      'another catalog': (d) => {...d, 'decompressed_sha256': 'a' * 64},
      'a path somewhere else': (d) => {...d, 'path': 'elsewhere/evil.gz'},
      'a bad hash': (d) => {...d, 'sha256': 'nope'},
      'a size that is not a number': (d) => {...d, 'size': '12'},
      'a zero size': (d) => {...d, 'decompressed_size': 0},
      'a missing field': (d) => {...d}..remove('size'),
    };
    bad.forEach((name, change) {
      test('a descriptor with $name', () async {
        publish(described: change(descriptor()));
        final phone = await launch();
        await service().stageCatalog(
          downloads: phone.store.downloads,
          version: _version,
          expectedSha256: catalogSha,
        );
        expect(storage.requested, [descriptorPath, rawPath]);
      });
    });

    test('a descriptor that is not JSON', () async {
      publish();
      storage.objects[descriptorPath] = utf8.encode('<html>');
      final phone = await launch();
      await service().stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      expect(storage.requested, [descriptorPath, rawPath]);
    });
  });

  group('interrupted download', () {
    test('keeps the partial, leaves the last good release active, and resumes '
        'with Range on the next tick', () async {
      publish();
      final half = gzBytes.length ~/ 2;
      final phone = await launch();
      final dropping = _AlwaysDropping(storage, gzPath, half);
      await expectLater(
        SyncService(
          appVersion: '1.0.0',
          httpClientFactory: () => dropping,
          availableBytes: (_) async => null,
        ).stageCatalog(
          downloads: phone.store.downloads,
          version: _version,
          expectedSha256: catalogSha,
        ),
        throwsA(anything),
      );

      final partial = File(stagingPath(phone.store, 'catalog.gz.staging'));
      expect(partial.lengthSync(), half);
      await expectLastGoodActive(phone.store);

      storage
        ..ranges.clear()
        ..dropAfter.clear();
      final staged = await service().stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      expect(storage.ranges, contains('bytes=$half-'));
      final result = await phone.store.activate(candidateFrom(staged));
      open.add((result as ReleaseActivated).generation);
      expect(result.generation.record.catalogVersion, _version);
    }, timeout: const Timeout(Duration(minutes: 2)));

    for (final status in [401, 403]) {
      test(
        'descriptor public denial $status reaches authenticated plain download',
        () async {
          publish();
          final phone = await launch();
          storage.publicFailures[descriptorPath] = (
            status,
            'public access denied',
          );
          storage.publicFailures[rawPath] = (status, 'public access denied');
          final staged = await service().stageCatalog(
            downloads: phone.store.downloads,
            version: _version,
            expectedSha256: catalogSha,
          );
          expect(storage.requested, [descriptorPath, rawPath, rawPath]);
          expect(storage.requested, isNot(contains(gzPath)));
          final activated = await phone.store.activate(candidateFrom(staged));
          open.add((activated as ReleaseActivated).generation);
          expect(
            await activated.generation.core.validateCatalogSnapshot(),
            _version,
          );
        },
      );
    }

    test(
      'a pending descriptor hits its actual deadline without using plain bytes',
      () async {
        publish();
        final phone = await launch();
        final pending = Completer<http.StreamedResponse>();
        storage.pending[descriptorPath] = pending;
        await expectLater(
          service().stageCatalog(
            downloads: phone.store.downloads,
            version: _version,
            expectedSha256: catalogSha,
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(storage.requested, [descriptorPath]);
        await expectLastGoodActive(phone.store);
        pending.complete(http.StreamedResponse(const Stream.empty(), 404));
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    for (final failure in ['server', 'timeout']) {
      test(
        'descriptor $failure is retryable and keeps both partials',
        () async {
          publish();
          final phone = await launch();
          phone.store.downloads.createSync(recursive: true);
          final plain = File(stagingPath(phone.store, 'catalog.staging'))
            ..writeAsBytesSync(
              catalogBytes.sublist(0, catalogBytes.length ~/ 2),
            );
          final gz = File(stagingPath(phone.store, 'catalog.gz.staging'))
            ..writeAsBytesSync(gzBytes.sublist(0, gzBytes.length ~/ 2));
          for (final file in [plain, gz]) {
            File('${file.path}.version').writeAsStringSync(_version);
          }
          if (failure == 'server') {
            storage.publicFailures[descriptorPath] = (
              503,
              '{"error":"internal_server_error"}',
            );
          } else {
            storage.errors[descriptorPath] = TimeoutException(
              'descriptor timed out',
            );
          }
          await expectLater(
            service().stageCatalog(
              downloads: phone.store.downloads,
              version: _version,
              expectedSha256: catalogSha,
            ),
            throwsA(
              failure == 'server'
                  ? isA<StorageException>()
                  : isA<TimeoutException>(),
            ),
          );
          expect(storage.requested, [descriptorPath]);
          expect(
            plain.readAsBytesSync(),
            catalogBytes.sublist(0, catalogBytes.length ~/ 2),
          );
          expect(gz.readAsBytesSync(), gzBytes.sublist(0, gzBytes.length ~/ 2));
          expect(File('${plain.path}.version').readAsStringSync(), _version);
          expect(File('${gz.path}.version').readAsStringSync(), _version);
          await expectLastGoodActive(phone.store);
          storage.publicFailures.clear();
          storage.errors.clear();
          final staged = await service().stageCatalog(
            downloads: phone.store.downloads,
            version: _version,
            expectedSha256: catalogSha,
          );
          expect(storage.ranges, contains('bytes=${gzBytes.length ~/ 2}-'));
          final activated = await phone.store.activate(candidateFrom(staged));
          open.add((activated as ReleaseActivated).generation);
          expect(
            await activated.generation.core.validateCatalogSnapshot(),
            _version,
          );
        },
      );
    }

    test(
      'same-version stale plain bytes fail checksum before activation then recover',
      () async {
        publish();
        storage.failures[gzPath] = (404, '{"error":"not_found"}');
        final phone = await launch();
        phone.store.downloads.createSync(recursive: true);
        final half = catalogBytes.length ~/ 2;
        final stale = Uint8List.fromList(catalogBytes.sublist(0, half));
        stale[32] ^= 0xff;
        final plain = File(stagingPath(phone.store, 'catalog.staging'))
          ..writeAsBytesSync(stale);
        File('${plain.path}.version').writeAsStringSync(_version);
        await expectLater(
          service().stageCatalog(
            downloads: phone.store.downloads,
            version: _version,
            expectedSha256: catalogSha,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'reason',
              contains('hash check'),
            ),
          ),
        );
        expect(storage.ranges, contains('bytes=$half-'));
        expect(plain.existsSync(), isFalse);
        expect(File('${plain.path}.version').existsSync(), isFalse);
        await expectLastGoodActive(phone.store);
        storage.ranges.clear();
        final staged = await service().stageCatalog(
          downloads: phone.store.downloads,
          version: _version,
          expectedSha256: catalogSha,
        );
        expect(storage.ranges, everyElement(isNull));
        final activated = await phone.store.activate(candidateFrom(staged));
        open.add((activated as ReleaseActivated).generation);
        expect(
          await activated.generation.core.validateCatalogSnapshot(),
          _version,
        );
      },
    );

    for (final unavailable in ['404', 'not_found', 'bad_hash', 'bad_gzip']) {
      for (final marker in [_version, '2026.01.01.000000']) {
        test(
          'compressed $unavailable preserves plain resume for marker $marker',
          () async {
            publish();
            final phone = await launch();
            phone.store.downloads.createSync(recursive: true);
            final half = catalogBytes.length ~/ 2;
            final plain = File(stagingPath(phone.store, 'catalog.staging'))
              ..writeAsBytesSync(catalogBytes.sublist(0, half));
            File('${plain.path}.version').writeAsStringSync(marker);
            if (unavailable == '404') {
              storage.failures[gzPath] = (404, '{"error":"not_found"}');
            } else if (unavailable == 'not_found') {
              storage.failures[gzPath] = (400, '{"error":"not_found"}');
            } else if (unavailable == 'bad_hash') {
              storage.objects[gzPath] = [1, 2, 3];
            } else {
              publish(
                gz: [1, 2, 3],
                described: descriptor(sha: _shaOf([1, 2, 3]), size: 3),
              );
            }
            final staged = await service().stageCatalog(
              downloads: phone.store.downloads,
              version: _version,
              expectedSha256: catalogSha,
            );
            expect(storage.requested, contains(rawPath));
            expect(storage.ranges.contains('bytes=$half-'), marker == _version);
            expect(File('${plain.path}.version').existsSync(), isFalse);
            final activated = await phone.store.activate(candidateFrom(staged));
            open.add((activated as ReleaseActivated).generation);
            expect(activated.generation.record.catalogVersion, _version);
          },
        );
      }
    }

    test(
      'a storage server failure keeps compressed download retryable',
      () async {
        publish();
        final phone = await launch();
        storage.failures[gzPath] = (503, '{"error":"internal_server_error"}');
        await expectLater(
          service().stageCatalog(
            downloads: phone.store.downloads,
            version: _version,
            expectedSha256: catalogSha,
          ),
          throwsA(isA<StorageException>()),
        );
        expect(storage.requested, isNot(contains(rawPath)));
        await expectLastGoodActive(phone.store);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a missing compressed object still uses verified plain bytes',
      () async {
        publish();
        final phone = await launch();
        storage.failures[gzPath] = (
          400,
          '{"error":"not_found","message":"Object not found"}',
        );
        final staged = await service().stageCatalog(
          downloads: phone.store.downloads,
          version: _version,
          expectedSha256: catalogSha,
        );
        expect(storage.requested, contains(rawPath));
        final activated = await phone.store.activate(candidateFrom(staged));
        open.add((activated as ReleaseActivated).generation);
        expect(activated.generation.record.catalogVersion, _version);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a transient failure does not spend the plain 66 MB download',
      () async {
        publish();
        final half = gzBytes.length ~/ 2;
        final phone = await launch();
        final client = _AlwaysDropping(storage, gzPath, half);
        await expectLater(
          SyncService(
            appVersion: '1.0.0',
            httpClientFactory: () => client,
            availableBytes: (_) async => null,
          ).stageCatalog(
            downloads: phone.store.downloads,
            version: _version,
            expectedSha256: catalogSha,
          ),
          throwsA(anything),
        );
        expect(storage.requested, isNot(contains(rawPath)));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('corrupt file', () {
    List<int> flipped(List<int> bytes) {
      final copy = Uint8List.fromList(bytes);
      copy[copy.length ~/ 2] ^= 0xff;
      return copy;
    }

    test('a gz with the wrong hash is deleted unopened, and the plain file '
        'still delivers the update', () async {
      publish(gz: flipped(gzBytes));
      final phone = await launch();
      final staged = await service().stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      expect(storage.requested, [descriptorPath, gzPath, rawPath]);
      expect(
        File(stagingPath(phone.store, 'catalog.gz.staging')).existsSync(),
        isFalse,
      );
      final result = await phone.store.activate(candidateFrom(staged));
      open.add((result as ReleaseActivated).generation);
      expect(result.generation.record.catalogSha256, catalogSha);
    });

    test('with both files corrupt nothing activates and the last good release '
        'stays', () async {
      publish(gz: flipped(gzBytes));
      storage.objects[rawPath] = flipped(catalogBytes);
      final phone = await launch();
      await expectLater(
        service().stageCatalog(
          downloads: phone.store.downloads,
          version: _version,
          expectedSha256: catalogSha,
        ),
        throwsA(isA<StateError>()),
      );
      expect(phone.store.downloads.listSync(), isEmpty);
      await expectLastGoodActive(phone.store);
    });

    test('a gz whose own hash is right but which holds another catalog never '
        'becomes the catalog', () async {
      final other = gzip.encode(utf8.encode('another catalog entirely'));
      publish(
        gz: other,
        described: descriptor(
          sha: _shaOf(other),
          size: other.length,
          decompressedSize: 24,
        ),
      );
      storage.objects.remove(rawPath);
      final phone = await launch();
      await expectLater(
        service().stageCatalog(
          downloads: phone.store.downloads,
          version: _version,
          expectedSha256: catalogSha,
        ),
        throwsA(anything),
      );
      expect(
        File(stagingPath(phone.store, 'catalog.staging')).existsSync(),
        isFalse,
      );
      await expectLastGoodActive(phone.store);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'garbage with a matching hash fails to decompress and is deleted',
      () async {
        final garbage = utf8.encode('this is not gzip');
        publish(
          gz: garbage,
          described: descriptor(sha: _shaOf(garbage), size: garbage.length),
        );
        final phone = await launch();
        final staged = await service().stageCatalog(
          downloads: phone.store.downloads,
          version: _version,
          expectedSha256: catalogSha,
        );
        expect(storage.requested.last, rawPath);
        expect(staged.existsSync(), isTrue);
      },
    );

    test('a truncated gz with a matching hash is refused', () async {
      final truncated = gzBytes.sublist(0, gzBytes.length ~/ 2);
      publish(
        gz: truncated,
        described: descriptor(sha: _shaOf(truncated), size: truncated.length),
      );
      final phone = await launch();
      await service().stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      expect(storage.requested.last, rawPath);
    });

    group('what comes out of the gz', () {
      Future<void> expectRefused(
        List<int> contents, {
        required String because,
        required String expectedSha,
        required int expectedBytes,
      }) async {
        final source = File(p.join(workspace.path, 'in.gz'))
          ..writeAsBytesSync(gzip.encode(contents));
        final target = File(p.join(workspace.path, 'out.db'));
        await expectLater(
          decompressCatalogFile(
            source: source.path,
            target: target.path,
            expectedSha256: expectedSha,
            expectedBytes: expectedBytes,
          ),
          throwsA(
            isA<CompressedCatalogRejected>().having(
              (error) => error.message,
              'message',
              contains(because),
            ),
          ),
        );
        expect(target.existsSync(), isFalse);
        expect(
          File('${target.path}.decompressing').existsSync(),
          isFalse,
          reason: 'a refused file gives its room back',
        );
      }

      test('the right size with the wrong bytes fails on its hash', () async {
        await expectRefused(
          utf8.encode('aaaa'),
          because: 'failed its hash check',
          expectedSha: _shaOf(utf8.encode('bbbb')),
          expectedBytes: 4,
        );
      });

      test('more than declared stops at what was declared', () async {
        final contents = Uint8List(8 << 10);
        await expectRefused(
          contents,
          because: 'expands past its declared size',
          expectedSha: _shaOf(contents),
          expectedBytes: 1 << 10,
        );
      });

      test('less than declared is refused, even with the right hash', () async {
        final contents = utf8.encode('short');
        await expectRefused(
          contents,
          because: 'holds 5 bytes',
          expectedSha: _shaOf(contents),
          expectedBytes: 6,
        );
      });
    });

    test('a gz of a good catalog that is not this one falls back to the plain '
        'file, which is the catalog that gets staged', () async {
      final other = p.join(workspace.path, 'other.db');
      await buildCatalog(other, version: _version, score: 12);
      final otherBytes = File(other).readAsBytesSync();
      expect(_shaOf(otherBytes), isNot(catalogSha));
      final otherGz = gzip.encode(otherBytes);
      publish(
        gz: otherGz,
        described: descriptor(sha: _shaOf(otherGz), size: otherGz.length),
      );
      final phone = await launch();
      final staged = await service().stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      final db = raw.sqlite3.open(staged.path);
      addTearDown(db.close);
      expect(
        db
            .select('SELECT quality_score_v4_100 AS score FROM products_core')
            .single['score'],
        88,
      );
      expect(storage.requested, contains(rawPath));
      expect(
        File(stagingPath(phone.store, 'catalog.gz.staging')).existsSync(),
        isFalse,
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a gz that expands past its declared size stops there, on a disk '
        'with room for only what was declared', () async {
      final bomb = gzip.encode(Uint8List(32 << 20));
      final source = File(p.join(workspace.path, 'bomb.gz'))
        ..writeAsBytesSync(bomb);
      final target = File(p.join(workspace.path, 'bomb.db'));
      await expectLater(
        decompressCatalogOffUiIsolate(
          source: source.path,
          target: target.path,
          expectedSha256: catalogSha,
          expectedBytes: 1 << 20,
        ),
        throwsA(isA<CompressedCatalogRejected>()),
      );
      expect(target.existsSync(), isFalse);
    });

    test('the decompressed file still has to pass the existing gates: a right '
        'hash holding the wrong version is refused', () async {
      final other = p.join(workspace.path, 'other.db');
      await buildCatalog(other, version: '2026.11.03.999999');
      catalogBytes = File(other).readAsBytesSync();
      gzBytes = gzip.encode(catalogBytes);
      catalogSha = _shaOf(catalogBytes);
      publish();
      final phone = await launch();
      await expectLater(
        service().stageCatalog(
          downloads: phone.store.downloads,
          version: _version,
          expectedSha256: catalogSha,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        File(stagingPath(phone.store, 'catalog.staging')).existsSync(),
        isFalse,
      );
      await expectLastGoodActive(phone.store);
    });

    test(
      'a catalog this build cannot read is refused after decompressing',
      () async {
        final other = p.join(workspace.path, 'future.db');
        await buildCatalog(other, version: _version, minAppVersion: '99.0.0');
        catalogBytes = File(other).readAsBytesSync();
        gzBytes = gzip.encode(catalogBytes);
        catalogSha = _shaOf(catalogBytes);
        publish();
        final phone = await launch();
        await expectLater(
          service().stageCatalog(
            downloads: phone.store.downloads,
            version: _version,
            expectedSha256: catalogSha,
          ),
          throwsA(isA<CatalogVersionGateException>()),
        );
        await expectLastGoodActive(phone.store);
      },
    );
  });

  group('kill during decompression', () {
    test('the partial file is never mistaken for a catalog, the last good '
        'release stays, and the next attempt needs no download', () async {
      // Big enough to take far longer than the polling below.
      final big = Uint8List(48 << 20);
      final seed = sha256.convert(catalogBytes).bytes;
      for (var i = 0; i < big.length; i += 4096) {
        big[i] = seed[i % seed.length] ^ (i >> 12);
      }
      final bigGz = gzip.encode(big);
      final source = File(p.join(workspace.path, 'big.gz'))
        ..writeAsBytesSync(bigGz);
      final target = File(p.join(workspace.path, 'big.db'));

      final exited = ReceivePort();
      final isolate = await Isolate.spawn(
        _decompressForKill,
        [source.path, target.path],
        onExit: exited.sendPort,
        errorsAreFatal: true,
      );
      final partial = File('${target.path}.decompressing');
      while (!partial.existsSync() || partial.lengthSync() == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      isolate.kill(priority: Isolate.immediate);
      await exited.first;
      expect(partial.existsSync(), isTrue);
      expect(partial.lengthSync(), lessThan(big.length));
      expect(
        target.existsSync(),
        isFalse,
        reason: 'only a whole file is named',
      );

      // The same state, in a real store's staging folder, with a whole gz.
      publish();
      final phone = await launch();
      phone.store.downloads.createSync(recursive: true);
      final gzStaging = File(stagingPath(phone.store, 'catalog.gz.staging'))
        ..writeAsBytesSync(gzBytes);
      File('${gzStaging.path}.version').writeAsStringSync(_version);
      File(
        stagingPath(phone.store, 'catalog.staging.decompressing'),
      ).writeAsBytesSync(catalogBytes.sublist(0, catalogBytes.length ~/ 2));

      final relaunched = await launch();
      expect(relaunched.store.active!.catalogVersion, _bundledCatalog);

      final staged = await service().stageCatalog(
        downloads: relaunched.store.downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      expect(storage.requested, [descriptorPath], reason: 'no gz download');
      final result = await relaunched.store.activate(candidateFrom(staged));
      open.add((result as ReleaseActivated).generation);
      expect(result.generation.record.catalogVersion, _version);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('full disk', () {
    int required() =>
        gzBytes.length + catalogBytes.length + kCatalogHeadroomBytes;

    test('the error that reaches crash reporting holds no disk reading, and '
        'Apple is told why the app reads one', () {
      expect(
        const CatalogStorageFullException().toString(),
        isNot(contains(RegExp(r'\d'))),
      );
      final manifest = File(
        'ios/Runner/PrivacyInfo.xcprivacy',
      ).readAsStringSync();
      expect(manifest, contains('NSPrivacyAccessedAPICategoryDiskSpace'));
      expect(manifest, contains('E174.1'));
      expect(
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
        contains('PrivacyInfo.xcprivacy in Resources'),
      );
    });

    test('falling back to the plain file checks for room again', () async {
      publish(gz: gzBytes.reversed.toList());
      final phone = await launch();
      var measured = 0;
      await expectLater(
        service(
          freeNow: () => measured++ == 0 ? required() : catalogBytes.length,
        ).stageCatalog(
          downloads: phone.store.downloads,
          version: _version,
          expectedSha256: catalogSha,
        ),
        throwsA(isA<CatalogStorageFullException>()),
      );
      expect(storage.requested, [descriptorPath, gzPath]);
      await expectLastGoodActive(phone.store);
    });

    for (final marker in [_version, '2026.01.01.000000']) {
      test(
        'plain marker $marker is handled before compressed room measurement',
        () async {
          publish();
          final phone = await launch();
          phone.store.downloads.createSync(recursive: true);
          final plain = File(stagingPath(phone.store, 'catalog.staging'))
            ..writeAsBytesSync(catalogBytes.sublist(0, 1024));
          File('${plain.path}.version').writeAsStringSync(marker);
          bool? measuredWithPlain;
          final staged =
              await service(
                freeNow: () {
                  measuredWithPlain = plain.existsSync();
                  return required() -
                      (plain.existsSync() && marker != _version ? 1 : 0);
                },
              ).stageCatalog(
                downloads: phone.store.downloads,
                version: _version,
                expectedSha256: catalogSha,
              );
          expect(measuredWithPlain, marker == _version);
          final activated = await phone.store.activate(candidateFrom(staged));
          open.add((activated as ReleaseActivated).generation);
          expect(
            await activated.generation.core.validateCatalogSnapshot(),
            _version,
          );
        },
      );
    }

    test(
      'same-version plain partial survives compressed room refusal',
      () async {
        publish();
        final phone = await launch();
        phone.store.downloads.createSync(recursive: true);
        final bytes = catalogBytes.sublist(0, 1024);
        final plain = File(stagingPath(phone.store, 'catalog.staging'))
          ..writeAsBytesSync(bytes);
        File('${plain.path}.version').writeAsStringSync(_version);
        await expectLater(
          service(free: 0).stageCatalog(
            downloads: phone.store.downloads,
            version: _version,
            expectedSha256: catalogSha,
          ),
          throwsA(isA<CatalogStorageFullException>()),
        );
        expect(plain.readAsBytesSync(), bytes);
        expect(File('${plain.path}.version').readAsStringSync(), _version);
        expect(storage.requested, [descriptorPath]);
        await expectLastGoodActive(phone.store);
      },
    );

    test('short by one byte: nothing is downloaded and the last good release '
        'stays', () async {
      publish();
      final phone = await launch();
      await expectLater(
        service(free: required() - 1).stageCatalog(
          downloads: phone.store.downloads,
          version: _version,
          expectedSha256: catalogSha,
        ),
        throwsA(isA<CatalogStorageFullException>()),
      );
      expect(storage.requested, [descriptorPath]);
      expect(phone.store.downloads.listSync(), isEmpty);
      await expectLastGoodActive(phone.store);
    });

    test('exactly enough room goes ahead', () async {
      publish();
      final phone = await launch();
      await service(free: required()).stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      expect(storage.requested, [descriptorPath, gzPath]);
    });

    test('the part already downloaded is not asked for twice', () async {
      publish();
      final phone = await launch();
      phone.store.downloads.createSync(recursive: true);
      final half = gzBytes.length ~/ 2;
      File(
        stagingPath(phone.store, 'catalog.gz.staging'),
      ).writeAsBytesSync(gzBytes.sublist(0, half));
      File(
        stagingPath(phone.store, 'catalog.gz.staging.version'),
      ).writeAsStringSync(_version);
      await service(free: required() - half).stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      expect(storage.ranges, contains('bytes=$half-'));
    });

    test(
      'partial files from a killed attempt are cleared before measuring',
      () async {
        publish();
        final phone = await launch();
        phone.store.downloads.createSync(recursive: true);
        final leftover = File(
          stagingPath(phone.store, 'catalog.staging.decompressing'),
        )..writeAsBytesSync(Uint8List(1024));
        var checkedWithLeftover = false;
        await service(
          freeNow: () {
            checkedWithLeftover = leftover.existsSync();
            return required();
          },
        ).stageCatalog(
          downloads: phone.store.downloads,
          version: _version,
          expectedSha256: catalogSha,
        );
        expect(checkedWithLeftover, isFalse);
      },
    );

    test('a phone that can not measure its disk goes ahead, because a failed '
        'write is safe anyway', () async {
      publish();
      final phone = await launch();
      await service().stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      expect(storage.requested, [descriptorPath, gzPath]);
    });

    test('a write that fails while decompressing removes the partial, keeps '
        'the gz, and does not fall back to the larger file', () async {
      publish();
      final phone = await launch();
      phone.store.downloads.createSync(recursive: true);
      // A directory where the output goes fails the write as a full disk does:
      // as a FileSystemException partway through staging. The real ENOSPC case
      // is in release_full_disk_test.dart.
      final blocked = Directory(
        stagingPath(phone.store, 'catalog.staging.decompressing'),
      );
      await expectLater(
        service(
          freeNow: () {
            blocked.createSync(recursive: true);
            return null;
          },
        ).stageCatalog(
          downloads: phone.store.downloads,
          version: _version,
          expectedSha256: catalogSha,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(storage.requested, isNot(contains(rawPath)));
      expect(
        File(stagingPath(phone.store, 'catalog.gz.staging')).existsSync(),
        isTrue,
      );
      await expectLastGoodActive(phone.store);
    });

    test('the kept previous release survives the update it pays for', () async {
      publish();
      final phone = await launch();
      final before = phone.store.active!.id;
      final staged = await service(free: required()).stageCatalog(
        downloads: phone.store.downloads,
        version: _version,
        expectedSha256: catalogSha,
      );
      final result = await phone.store.activate(candidateFrom(staged));
      open.add((result as ReleaseActivated).generation);
      expect(
        Directory(p.join(documents.path, 'releases', before)).existsSync(),
        isTrue,
      );
      final relaunched = await launch();
      expect(relaunched.store.active!.catalogVersion, _version);
      expect(
        Directory(p.join(documents.path, 'releases', before)).existsSync(),
        isTrue,
      );
    });
  });

  test(
    'availableDiskBytes reads this disk, within a few percent of df',
    () async {
      final measured = await availableDiskBytes(workspace.path);
      final df = await Process.run('df', ['-k', workspace.path]);
      final parts = (df.stdout as String)
          .trim()
          .split('\n')
          .last
          .split(RegExp(r'\s+'));
      final expected = int.parse(parts[3]) * 1024;
      expect(measured, isNotNull);
      expect((measured! - expected).abs() / expected, lessThan(0.05));
    },
  );

  test(
    'availableDiskBytes says it does not know for a path it can not read',
    () async {
      expect(await availableDiskBytes('/no/such/path/here'), isNull);
    },
  );
}

/// Every response to [path] drops after [after] bytes.
class _AlwaysDropping extends http.BaseClient {
  _AlwaysDropping(this.storage, this.path, this.after);

  final _FakeStorage storage;
  final String path;
  final int after;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    storage.dropAfter[path] = after;
    return storage.send(request);
  }
}

void _decompressForKill(List<String> paths) {
  // Unverifiable on purpose: this one is only ever killed.
  unawaited(
    decompressCatalogFile(
      source: paths[0],
      target: paths[1],
      expectedSha256: 'a' * 64,
      expectedBytes: 1 << 40,
    ),
  );
}
