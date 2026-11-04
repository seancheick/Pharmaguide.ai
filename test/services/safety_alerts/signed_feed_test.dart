import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pharmaguide/services/release_manifest.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legacy_readers/extended_feed_repository.dart' as extended_reader;
import 'legacy_readers/pre_skip_repository.dart' as pre_skip;
import 'legacy_readers/skip_unknown_repository.dart' as skip_unknown;
import 'signed_feed_support.dart';

final _extendedBytes = File(
  'test/fixtures/safety_alerts/interaction_rule_feed.json',
).readAsBytesSync();
final _baseBytes = File(
  'test/fixtures/safety_alerts/interaction_rule_base_feed.json',
).readAsBytesSync();

const _basePath = 'safety/feed.json';
const _extendedPath = 'safety/extended.json';
const _cacheKey = 'safety_alert_release_v1';
const _watermarkKey = 'safety_alert_baseline_revisions_v1';
const _allAlerts = [
  'SA_9999_0001',
  'SA_9999_0002',
  'SA_9999_0003',
  'SA_9999_0004',
];
const _banAndRecall = ['SA_9999_0002', 'SA_9999_0004'];

String _checksum(List<int> bytes) => 'sha256:${sha256.convert(bytes)}';

Map<String, Object?> get _extendedEntry => {
  'path': _extendedPath,
  'checksum': _checksum(_extendedBytes),
};

String get _goodStatement => feedStatement(
  path: _basePath,
  checksum: _checksum(_baseBytes),
  extended: _extendedEntry,
);

/// A release row, as the publisher writes it, that a test can then damage.
class _Server {
  _Server({this.signed, this.requests});

  /// The whole `signed_feed` block; null leaves it out.
  Map<String, Object?>? signed;
  Map<String, Object?> row = {
    'feed_path': _basePath,
    'checksum': _checksum(_baseBytes),
  };
  Map<String, List<int>> files = {
    _basePath: _baseBytes,
    _extendedPath: _extendedBytes,
  };
  bool offline = false;
  final List<http.Request>? requests;
  final downloads = <String>[];

  SupabaseClient client() {
    final client = SupabaseClient(
      'https://example.test',
      'test-key',
      httpClient: MockClient((request) async {
        requests?.add(request);
        if (offline) throw http.ClientException('offline');
        if (request.url.path.contains('/storage/')) {
          downloads.add(request.url.path);
          for (final file in files.entries) {
            if (request.url.path.endsWith(file.key)) {
              return http.Response.bytes(file.value, 200, request: request);
            }
          }
          throw http.ClientException('missing');
        }
        return http.Response(
          jsonEncode({
            ...row,
            'manifest': {
              'extended_feed': _extendedEntry,
              if (signed != null) 'signed_feed': signed,
              ...?row['manifest'] as Map<String, Object?>?,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    return client;
  }
}

Future<_Server> _signedServer({List<http.Request>? requests}) async => _Server(
  signed: {
    'statement': _goodStatement,
    'signature': await signText(_goodStatement),
  },
  requests: requests,
);

SafetyAlertRepository _repository(
  _Server server,
  _MemoryPreferences preferences, {
  Map<String, String> keys = testAlertFeedKeys,
}) => SafetyAlertRepository(
  client: server.client(),
  preferences: preferences,
  verificationKeys: keys,
);

List<String> _ids(SafetyAlertRelease release) =>
    release.alerts.map((alert) => alert.alertId).toList()..sort();

void _expectNoAllClear(SafetyAlertRelease release) {
  expect(release.isComplete, isFalse);
  expect(release.neverVerified, isTrue);
}

/// Each one signs or breaks a block a phone must not trust.
final Map<String, Future<Map<String, Object?>?> Function()> _untrusted = {
  'no signature block': () async => null,
  'a statement with no signature': () async => {'statement': _goodStatement},
  'a signature with no statement': () async => {
    'signature': await signText(_goodStatement),
  },
  'a signature that is not a string': () async => {
    'statement': _goodStatement,
    'signature': 7,
  },
  'a malformed signature': () async => {
    'statement': _goodStatement,
    'signature': 'no separator',
  },
  'a signature that is not base64': () async => {
    'statement': _goodStatement,
    'signature': '$testAlertFeedKeyId:%%%',
  },
  'a signature of the wrong length': () async => {
    'statement': _goodStatement,
    'signature': '$testAlertFeedKeyId:AAAA',
  },
  'an edited statement': () async => {
    'statement': _goodStatement.replaceFirst(
      '"release_sequence":1',
      '"release_sequence":2',
    ),
    'signature': await signText(_goodStatement),
  },
  'an unpinned key id': () async => {
    'statement': _goodStatement,
    'signature': await signText(
      _goodStatement,
      keyId: 'someone-else',
      seed: List.filled(32, 9),
    ),
  },
  'another key claiming the pinned id': () async => {
    'statement': _goodStatement,
    'signature': await signText(_goodStatement, seed: List.filled(32, 9)),
  },
  'a statement naming another key than signed it': () async {
    final statement = feedStatement(
      path: _basePath,
      checksum: _checksum(_baseBytes),
      extended: _extendedEntry,
      keyId: 'someone-else',
    );
    return {'statement': statement, 'signature': await signText(statement)};
  },
  'a signed catalog manifest': () async {
    final statement = jsonEncode({
      'format': 1,
      'key_id': testAlertFeedKeyId,
      'release_sequence': 1,
      'catalog': {'path': _basePath, 'sha256': '0' * 64},
      'rules': null,
      'min_rules_version': '1.0.0',
      'blocked_versions': {'catalog': <String>[], 'rules': <String>[]},
    });
    return {'statement': statement, 'signature': await signText(statement)};
  },
  'a statement for another purpose': () async {
    final statement = feedStatement(
      path: _basePath,
      checksum: _checksum(_baseBytes),
      purpose: 'something_else',
    );
    return {'statement': statement, 'signature': await signText(statement)};
  },
  'a statement format this build can not read': () async {
    final statement = feedStatement(
      path: _basePath,
      checksum: _checksum(_baseBytes),
      format: 2,
    );
    return {'statement': statement, 'signature': await signText(statement)};
  },
  'a signed text that is not JSON': () async => {
    'statement': 'not json',
    'signature': await signText('not json'),
  },
  'a sequence that is not positive': () async {
    final statement = feedStatement(
      path: _basePath,
      checksum: _checksum(_baseBytes),
      sequence: 0,
    );
    return {'statement': statement, 'signature': await signText(statement)};
  },
  'a malformed base checksum': () async {
    final statement = feedStatement(path: _basePath, checksum: 'not a hash');
    return {'statement': statement, 'signature': await signText(statement)};
  },
};

void main() {
  group('a good signature', () {
    test('this build reads every alert, as a complete check', () async {
      final preferences = _MemoryPreferences();
      final release = await _repository(
        await _signedServer(),
        preferences,
      ).loadCurrent();

      expect(_ids(release), _allAlerts);
      expect(release.isComplete, isTrue);
      expect(release.neverVerified, isFalse);
      expect(preferences.values[_cacheKey], isNotNull);
    });

    test('the exact text and signature the pipeline produces verify', () async {
      // Two pins, one vector: scripts/tests/test_sync_safety_alerts.py pins
      // these. It is the only place both repos are checked on the same bytes.
      const statement =
          '{"base_feed":{"checksum":"sha256:7564e689beaa6fe47a794d3121ac715c211a487476098e3c80c6b0bde2a940c5",'
          '"path":"safety-alerts/sha256/7564e689beaa6fe47a794d3121ac715c211a487476098e3c80c6b0bde2a940c5.json"},'
          '"extended_feed":{"checksum":"sha256:e0f20b54bcdf8aa77eef02c2c8420644adb390510546f8121e8e3359f3c1eb8f",'
          '"path":"safety-alerts/sha256/e0f20b54bcdf8aa77eef02c2c8420644adb390510546f8121e8e3359f3c1eb8f.json"},'
          '"format":1,"key_id":"alert-feed-test","purpose":"safety_alert_feed","release_sequence":7}';
      const signature =
          'alert-feed-test:NvakCzcQUs9jnDjhng2OJzMIgnBOoNzTu/zGCJ410aHW8G6b1d6FHbOXMSQPxgEN3bZdzjR6+9mHIOy9tSe+AQ==';
      final server =
          _Server(signed: {'statement': statement, 'signature': signature})
            ..files = {
              '7564e689beaa6fe47a794d3121ac715c211a487476098e3c80c6b0bde2a940c5.json':
                  _baseBytes,
              'e0f20b54bcdf8aa77eef02c2c8420644adb390510546f8121e8e3359f3c1eb8f.json':
                  _extendedBytes,
            };

      final release = await _repository(
        server,
        _MemoryPreferences(),
      ).loadCurrent();

      expect(_ids(release), _allAlerts);
      expect(release.isComplete, isTrue);
    });

    test('a phone that was offline keeps it as a verified copy', () async {
      final server = await _signedServer();
      final preferences = _MemoryPreferences();
      final repository = _repository(server, preferences);
      await repository.loadCurrent();

      server.offline = true;
      final release = await repository.loadCurrent();

      expect(_ids(release), _allAlerts);
      expect(release.isComplete, isFalse);
      expect(release.neverVerified, isFalse);
    });

    test('the unsigned row fields decide nothing', () async {
      final forged = utf8.encode('{"alerts":[]}');
      final server = await _signedServer()
        ..row = {
          'feed_path': 'safety/forged.json',
          'checksum': _checksum(forged),
          'manifest': {
            // Hiding the superset from new builds takes more than the row.
            'extended_feed': null,
          },
        }
        ..files = {
          'safety/forged.json': forged,
          _basePath: _baseBytes,
          _extendedPath: _extendedBytes,
        };

      final release = await _repository(
        server,
        _MemoryPreferences(),
      ).loadCurrent();

      expect(_ids(release), _allAlerts);
      expect(server.downloads.join(), isNot(contains('forged')));
    });

    test('bytes that do not match the signed checksum are refused', () async {
      final server = await _signedServer()
        ..files = {
          _basePath: utf8.encode('{"alerts":[]}'),
          _extendedPath: utf8.encode('{"alerts":[]}'),
        };

      _expectNoAllClear(
        await _repository(server, _MemoryPreferences()).loadCurrent(),
      );
    });
  });

  group('with nothing saved, a phone gets no all-clear from', () {
    for (final entry in _untrusted.entries) {
      test(entry.key, () async {
        final preferences = _MemoryPreferences();
        final server = _Server(signed: await entry.value());

        final release = await _repository(server, preferences).loadCurrent();

        expect(release.alerts, isEmpty);
        _expectNoAllClear(release);
        expect(preferences.values, isEmpty, reason: 'nothing may be saved');
        expect(server.downloads, isEmpty, reason: 'checked before any fetch');
      });
    }
  });

  group('a good saved copy is kept through', () {
    for (final entry in _untrusted.entries) {
      test(entry.key, () async {
        final preferences = _MemoryPreferences();
        final server = await _signedServer();
        final repository = _repository(server, preferences);
        await repository.loadCurrent();
        final saved = Map.of(preferences.values);

        server.signed = await entry.value();
        final release = await repository.loadCurrent();

        expect(_ids(release), _allAlerts);
        expect(release.isComplete, isFalse);
        expect(release.neverVerified, isFalse);
        expect(preferences.values, saved);
      });
    }
  });

  group('no key', () {
    test('a build with no keys verifies nothing and gives no all-clear, '
        'even for a correctly signed feed', () async {
      final preferences = _MemoryPreferences();
      final release = await _repository(
        await _signedServer(),
        preferences,
        keys: const {},
      ).loadCurrent();

      expect(release.alerts, isEmpty);
      _expectNoAllClear(release);
      expect(preferences.values, isEmpty);
    });

    test('the published test key never counts by default', () {
      expect(
        kAlertFeedVerificationKeys.values,
        isNot(contains(testAlertFeedPublicKey)),
      );
    });
  });

  group('an older signed release', () {
    Future<Map<String, Object?>> signedAt(int sequence) => signedFeedBlock(
      path: _basePath,
      checksum: _checksum(_baseBytes),
      extended: _extendedEntry,
      sequence: sequence,
    );

    test('replayed: refused, and the newer copy stays', () async {
      final server = _Server(signed: await signedAt(5));
      final preferences = _MemoryPreferences();
      final repository = _repository(server, preferences);
      await repository.loadCurrent();
      final saved = Map.of(preferences.values);

      // A genuine signature on a withdrawn state of the world.
      final empty = utf8.encode('{"alerts":[]}');
      final replay = feedStatement(
        path: 'safety/old.json',
        checksum: _checksum(empty),
        sequence: 4,
      );
      server
        ..files = {'safety/old.json': empty}
        ..signed = {'statement': replay, 'signature': await signText(replay)};
      final release = await repository.loadCurrent();

      expect(_ids(release), _allAlerts);
      expect(release.isComplete, isFalse);
      expect(preferences.values, saved);
    });

    test('the same sequence again is a retry, and is read', () async {
      final server = _Server(signed: await signedAt(5));
      final repository = _repository(server, _MemoryPreferences());
      await repository.loadCurrent();

      expect((await repository.loadCurrent()).isComplete, isTrue);
    });

    test('a higher sequence moves on, and sets the new floor', () async {
      final server = _Server(signed: await signedAt(5));
      final repository = _repository(server, _MemoryPreferences());
      await repository.loadCurrent();

      server.signed = await signedAt(6);
      expect((await repository.loadCurrent()).isComplete, isTrue);

      server.signed = await signedAt(5);
      expect((await repository.loadCurrent()).isComplete, isFalse);
    });

    test('the same bytes under a higher sequence still raise the floor, '
        'when the extended feed is not fetched again', () async {
      final server = _Server(signed: await signedAt(5));
      final repository = _repository(server, _MemoryPreferences());
      await repository.loadCurrent();
      server.downloads.clear();

      server.signed = await signedAt(6);
      expect((await repository.loadCurrent()).isComplete, isTrue);
      expect(server.downloads, isEmpty);

      server.signed = await signedAt(5);
      expect((await repository.loadCurrent()).isComplete, isFalse);
    });
  });

  group('a saved copy', () {
    test('signed by a key this build no longer trusts stays on screen, '
        'with no all-clear', () async {
      final server = await _signedServer();
      final preferences = _MemoryPreferences();
      await _repository(server, preferences).loadCurrent();

      server.offline = true;
      final release = await _repository(
        server,
        preferences,
        keys: const {},
      ).loadCurrent();

      expect(_ids(release), _allAlerts);
      _expectNoAllClear(release);
    });

    test('still verifies across a rotation that keeps its key', () async {
      final server = await _signedServer();
      final preferences = _MemoryPreferences();
      await _repository(server, preferences).loadCurrent();

      server.offline = true;
      final release = await _repository(
        server,
        preferences,
        keys: {...testAlertFeedKeys, 'next-key': 'ab' * 32},
      ).loadCurrent();

      expect(release.neverVerified, isFalse);
    });

    test('whose signature names other bytes is not vouched for', () async {
      final server = await _signedServer();
      final preferences = _MemoryPreferences();
      await _repository(server, preferences).loadCurrent();

      final other = feedStatement(
        path: _basePath,
        checksum: 'sha256:${'0' * 64}',
      );
      final saved =
          jsonDecode(preferences.values[_cacheKey]!) as Map<String, dynamic>;
      saved['signed_feed'] = {
        'statement': other,
        'signature': await signText(other),
      };
      preferences.values[_cacheKey] = jsonEncode(saved);

      server.offline = true;
      final release = await _repository(server, preferences).loadCurrent();

      expect(_ids(release), _allAlerts);
      _expectNoAllClear(release);
    });

    test(
      'with a damaged signature block keeps its alerts, with no all-clear',
      () async {
        final server = await _signedServer();
        final preferences = _MemoryPreferences();
        await _repository(server, preferences).loadCurrent();

        final saved =
            jsonDecode(preferences.values[_cacheKey]!) as Map<String, dynamic>;
        saved['signed_feed'] = 'damaged';
        preferences.values[_cacheKey] = jsonEncode(saved);

        server.offline = true;
        final repository = _repository(server, preferences);
        final release = await repository.loadCurrent();

        expect(_ids(release), _allAlerts);
        _expectNoAllClear(release);
        expect(await repository.loadCachedAlerts(), hasLength(4));
      },
    );
  });

  group('a copy an older build saved', () {
    /// A real copy, written by the real old reader on this phone.
    Future<_MemoryPreferences> savedByTheOldBuild(_Server server) async {
      final preferences = _MemoryPreferences();
      await extended_reader.SafetyAlertRepository(
        client: server.client(),
        preferences: preferences,
      ).loadCurrent();
      return preferences;
    }

    test('offline: its alerts stay, and it gives no all-clear', () async {
      final server = await _signedServer();
      final preferences = await savedByTheOldBuild(server);

      server.offline = true;
      final release = await _repository(server, preferences).loadCurrent();

      expect(_ids(release), _allAlerts);
      _expectNoAllClear(release);
    });

    test('online: the first verified fetch replaces it', () async {
      final server = await _signedServer();
      final preferences = await savedByTheOldBuild(server);
      server.downloads.clear();

      final repository = _repository(server, preferences);
      final release = await repository.loadCurrent();

      expect(_ids(release), _allAlerts);
      expect(release.isComplete, isTrue);
      expect(release.neverVerified, isFalse);
      // The same checksum must not let the unverified copy answer for the
      // release, or this phone would stay without an all-clear for good.
      expect(server.downloads, isNotEmpty);

      server.offline = true;
      expect((await repository.loadCurrent()).neverVerified, isFalse);
    });

    test('a bad signature does not promote it', () async {
      final server = await _signedServer();
      final preferences = await savedByTheOldBuild(server);

      server.signed = null;
      final release = await _repository(server, preferences).loadCurrent();

      expect(_ids(release), _allAlerts);
      _expectNoAllClear(release);
    });
  });

  group('builds already on phones, on the real old path', () {
    /// One release row each: the publisher's, and one with its signature
    /// damaged. Old builds can't tell them apart, which is the point.
    Future<List<_Server>> servers() async => [
      await _signedServer(),
      _Server(signed: {'statement': 'damaged', 'signature': 'damaged'}),
      _Server(),
    ];

    test('before the skip: the ban and the recall, complete', () async {
      for (final server in await servers()) {
        final release = await pre_skip.SafetyAlertRepository(
          client: server.client(),
          preferences: _MemoryPreferences(),
        ).loadCurrent();

        expect(
          release.alerts.map((alert) => alert.alertId).toList()..sort(),
          _banAndRecall,
        );
        expect(release.isComplete, isTrue);
      }
    });

    test('with the skip: the ban and the recall, complete', () async {
      for (final server in await servers()) {
        final release = await skip_unknown.SafetyAlertRepository(
          client: server.client(),
          preferences: _MemoryPreferences(),
        ).loadCurrent();

        expect(
          release.alerts.map((alert) => alert.alertId).toList()..sort(),
          _banAndRecall,
        );
        expect(release.isComplete, isTrue);
      }
    });

    test('with the extended feed: every alert, complete', () async {
      for (final server in await servers()) {
        final release = await extended_reader.SafetyAlertRepository(
          client: server.client(),
          preferences: _MemoryPreferences(),
        ).loadCurrent();

        expect(
          release.alerts.map((alert) => alert.alertId).toList()..sort(),
          _allAlerts,
        );
        expect(release.isComplete, isTrue);
        expect(release.neverVerified, isFalse);
      }
    });

    test('what they read is unchanged: the same bytes and row fields', () async {
      // Pinned in the pipeline as FAKE_BASE_FEED_SHA256. The signature is
      // detached so these stay exactly what every installed build checks.
      expect(
        _checksum(_baseBytes),
        'sha256:7564e689beaa6fe47a794d3121ac715c211a487476098e3c80c6b0bde2a940c5',
      );
      expect(utf8.decode(_baseBytes), isNot(contains('signed_feed')));
    });
  });

  group('the fetch', () {
    String describe(http.Request request) => [
      request.method,
      request.url,
      request.body,
      (request.headers.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((header) => '${header.key}=${header.value}')
          .join('&'),
    ].join(' | ');

    test('sends exactly what the build before it sent', () async {
      final before = <http.Request>[];
      await extended_reader.SafetyAlertRepository(
        client: (await _signedServer(requests: before)).client(),
        preferences: _MemoryPreferences(),
      ).loadCurrent();

      final after = <http.Request>[];
      final release = await _repository(
        await _signedServer(requests: after),
        _MemoryPreferences(),
      ).loadCurrent();

      expect(release.isComplete, isTrue);
      expect(before, isNotEmpty);
      expect(after.map(describe).toList(), before.map(describe).toList());
    });

    test('and carries nothing about medications', () async {
      final requests = <http.Request>[];
      await _repository(
        await _signedServer(requests: requests),
        _MemoryPreferences(),
      ).loadCurrent();

      expect(requests, isNotEmpty);
      for (final request in requests) {
        final sent = describe(request).toLowerCase();
        for (final private in ['medication', 'rxcui', 'drug', 'class:']) {
          expect(sent, isNot(contains(private)));
        }
      }
    });
  });

  group('one signing path', () {
    test('a feed statement can not pass as a catalog release', () async {
      await expectLater(
        ReleaseManifest.verify(
          signedRelease: _goodStatement,
          signature: await signText(_goodStatement),
          keys: testAlertFeedKeys,
        ),
        throwsA(isA<ReleaseManifestException>()),
      );
    });

    test('the catalog check still refuses what it always refused', () async {
      await expectLater(
        verifySignedText(
          text: _goodStatement,
          signature: await signText(_goodStatement),
          keys: const {},
        ),
        throwsA(isA<ReleaseManifestException>()),
      );
      expect(
        await verifySignedText(
          text: _goodStatement,
          signature: await signText(_goodStatement),
          keys: testAlertFeedKeys,
        ),
        testAlertFeedKeyId,
      );
    });
  });

  group('a store build with no key', () {
    Future<ProcessResult> check(String source, {String? distribution}) async {
      final directory = Directory.systemTemp.createTempSync('alert_key_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/release_manifest.dart')
        ..writeAsStringSync(source);
      return Process.run(
        'bash',
        ['scripts/require_alert_feed_key.sh', file.path],
        environment: {'PHARMAGUIDE_IOS_DISTRIBUTION': distribution ?? ''},
      );
    }

    const empty = 'const Map<String, String> _kProductionAlertFeedKeys = {};';
    const pinned =
        "const Map<String, String> _kProductionAlertFeedKeys = {\n"
        "  'alert-feed-2026-11': 'ab',\n};";

    test('is refused, because it could never verify a feed', () async {
      final result = await check(empty);
      expect(result.exitCode, isNot(0));
      expect('${result.stderr}', contains('RELEASE_SIGNING_RUNBOOK'));
    });

    test('a pinned key is allowed', () async {
      expect((await check(pinned)).exitCode, 0);
    });

    test('a TestFlight build is allowed, for testing before the key', () async {
      expect((await check(empty, distribution: 'testflight')).exitCode, 0);
    });

    test('a source that no longer names the list is refused', () async {
      expect((await check('// moved')).exitCode, isNot(0));
    });

    test('the Makefile runs it before both store builds', () {
      final makefile = File('Makefile').readAsStringSync();
      for (final target in ['build-ios', 'build-android']) {
        expect(
          RegExp(
            '^$target:[^\\n]*require-alert-feed-key',
            multiLine: true,
          ).hasMatch(makefile),
          isTrue,
          reason: target,
        );
      }
    });
  });

  test('the watermark is only written from a copy a build has read', () async {
    final preferences = _MemoryPreferences();
    await _repository(_Server(), preferences).loadCurrent();
    expect(preferences.values.containsKey(_watermarkKey), isFalse);
  });
}

class _MemoryPreferences implements SharedPreferencesAsync {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
