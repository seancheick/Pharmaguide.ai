// What a signed release proves, and the pair rule it carries.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/release_manifest.dart';

import 'release_fixtures.dart';

const _sha = 'aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11';

void main() {
  late ReleaseSigner signer;

  setUpAll(() async => signer = await ReleaseSigner.create());

  String text({
    int sequence = 5,
    String? rulesVersion = '1.0.16',
    String minRulesVersion = '1.0.15',
    String catalogSchema = '2.5.0',
    String rulesSchema = '4.0.0',
    String catalogMinApp = '1.0.0',
    List<String> blockedCatalog = const [],
    List<String> blockedRules = const [],
  }) => signer.manifestText(
    sequence: sequence,
    catalogVersion: '2026.11.03.120000',
    catalogSha256: _sha,
    catalogSchema: catalogSchema,
    catalogMinApp: catalogMinApp,
    rulesVersion: rulesVersion,
    rulesSha256: rulesVersion == null ? null : _sha,
    rulesSchema: rulesSchema,
    minRulesVersion: minRulesVersion,
    blockedCatalog: blockedCatalog,
    blockedRules: blockedRules,
  );

  Future<ReleaseManifest> verified(String signedRelease) async =>
      ReleaseManifest.verify(
        signedRelease: signedRelease,
        signature: await signer.sign(signedRelease),
        keys: signer.keys,
      );

  Matcher refused(String fragment) => throwsA(
    isA<ReleaseManifestException>().having(
      (e) => e.message,
      'message',
      contains(fragment),
    ),
  );

  group('authenticity', () {
    test('reads the fields from the verified bytes', () async {
      final manifest = await verified(
        text(blockedCatalog: ['c1'], blockedRules: ['r1']),
      );
      expect(manifest.sequence, 5);
      expect(manifest.catalog.version, '2026.11.03.120000');
      expect(manifest.catalog.sha256, _sha);
      expect(manifest.rules!.version, '1.0.16');
      expect(manifest.minRulesVersion, '1.0.15');
      expect(manifest.blockedCatalog, {'c1'});
      expect(manifest.blockedRules, {'r1'});
    });

    test('a single changed byte fails', () async {
      final original = text();
      final signature = await signer.sign(original);
      await expectLater(
        ReleaseManifest.verify(
          signedRelease: original.replaceFirst('1.0.16', '1.0.17'),
          signature: signature,
          keys: signer.keys,
        ),
        refused('Invalid release signature'),
      );
    });

    test(
      'whitespace counts: the check is over the bytes, not the meaning',
      () async {
        final original = text();
        await expectLater(
          ReleaseManifest.verify(
            signedRelease: '$original ',
            signature: await signer.sign(original),
            keys: signer.keys,
          ),
          refused('Invalid release signature'),
        );
      },
    );

    test('an unknown key fails', () async {
      final other = await ReleaseSigner.create(keyId: 'other');
      final original = other.manifestText(
        sequence: 1,
        catalogVersion: '2026.11.03.120000',
        catalogSha256: _sha,
      );
      await expectLater(
        ReleaseManifest.verify(
          signedRelease: original,
          signature: await other.sign(original),
          keys: signer.keys,
        ),
        refused('Unknown release key'),
      );
    });

    test('a known key id with another key\'s signature fails', () async {
      final other = await ReleaseSigner.create(keyId: signer.keyId);
      final original = text();
      await expectLater(
        ReleaseManifest.verify(
          signedRelease: original,
          signature: await other.sign(original),
          keys: signer.keys,
        ),
        refused('Invalid release signature'),
      );
    });

    test('text signed by one trusted key but naming another fails', () async {
      final other = await ReleaseSigner.create(keyId: 'other');
      final original = text();
      await expectLater(
        ReleaseManifest.verify(
          signedRelease: original,
          signature: await other.sign(original),
          keys: {...signer.keys, ...other.keys},
        ),
        refused('wrong key'),
      );
    });

    for (final signature in [
      '',
      'no-separator',
      ':abc',
      'test-1:not base64!',
      'test-1:AAAA',
    ]) {
      test('malformed signature "$signature" fails', () async {
        await expectLater(
          ReleaseManifest.verify(
            signedRelease: text(),
            signature: signature,
            keys: signer.keys,
          ),
          throwsA(isA<ReleaseManifestException>()),
        );
      });
    }

    test('a malformed key in the build fails closed', () async {
      final original = text();
      await expectLater(
        ReleaseManifest.verify(
          signedRelease: original,
          signature: await signer.sign(original),
          keys: {signer.keys.keys.single: 'zz'},
        ),
        throwsA(isA<ReleaseManifestException>()),
      );
    });

    test('verifies what the pipeline signer produced', () async {
      // From scripts/tests/test_release_manifest.py in the pipeline, generated
      // by scripts/release_manifest.py. Both repos pin it, so a change to the
      // canonical text fails on one side or the other.
      final manifest = await ReleaseManifest.verify(
        signedRelease: _pythonVector,
        signature: _pythonSignature,
        keys: {'vector-key-1': _pythonPublicKey},
      );
      expect(manifest.sequence, 42);
      expect(manifest.rules!.version, '1.0.16');
      expect(manifest.blockedRules, {'1.0.14'});

      final catalogOnly = await ReleaseManifest.verify(
        signedRelease: _pythonCatalogOnly,
        signature: _pythonCatalogOnlySignature,
        keys: {'vector-key-1': _pythonPublicKey},
      );
      expect(catalogOnly.rules, isNull);
    });
  });

  group('parsing fails closed on signed but unusable text', () {
    Future<void> expectRefused(
      Map<String, Object?> Function(Map<String, Object?>) edit,
    ) async {
      final edited = jsonEncode(
        edit(jsonDecode(text()) as Map<String, Object?>),
      );
      await expectLater(
        verified(edited),
        throwsA(isA<ReleaseManifestException>()),
      );
    }

    test('a newer format', () => expectRefused((m) => m..['format'] = 2));
    test(
      'a format that is not a number',
      () => expectRefused((m) => m..['format'] = '1'),
    );
    test(
      'no sequence',
      () => expectRefused((m) => m..remove('release_sequence')),
    );
    test(
      'sequence zero',
      () => expectRefused((m) => m..['release_sequence'] = 0),
    );
    test(
      'no pair floor',
      () => expectRefused((m) => m..remove('min_rules_version')),
    );
    test(
      'no blocked list',
      () => expectRefused((m) => m..remove('blocked_versions')),
    );
    test('no catalog', () => expectRefused((m) => m..remove('catalog')));
    test(
      'a blocked entry that is not text',
      () => expectRefused(
        (m) => m
          ..['blocked_versions'] = {
            'catalog': [1],
            'rules': <String>[],
          },
      ),
    );
    test(
      'a hash that is not SHA-256',
      () => expectRefused(
        (m) => m
          ..['catalog'] = {
            ...(m['catalog']! as Map).cast<String, Object?>(),
            'sha256': 'abc',
          },
      ),
    );

    test('text that is not JSON', () async {
      await expectLater(verified('not json'), refused('not JSON'));
    });
  });

  group('the pair rule', () {
    test('named rules at the floor pass', () async {
      (await verified(
        text(rulesVersion: '1.0.15'),
      )).requireCompatible(currentRulesVersion: '1.0.1', appVersion: '1.0.0');
    });

    test(
      'named rules under the floor are refused, whatever the phone has',
      () async {
        final manifest = await verified(text(rulesVersion: '1.0.14'));
        expect(
          () => manifest.requireCompatible(
            currentRulesVersion: '1.0.99',
            appVersion: '1.0.0',
          ),
          refused('needs rules'),
        );
      },
    );

    test('catalog-only: the phone\'s rules must reach the floor', () async {
      final manifest = await verified(text(rulesVersion: null));
      manifest.requireCompatible(
        currentRulesVersion: '1.0.15',
        appVersion: '1.0.0',
      );
      expect(
        () => manifest.requireCompatible(
          currentRulesVersion: '1.0.14',
          appVersion: '1.0.0',
        ),
        refused('needs rules'),
      );
    });

    test('catalog-only on a phone with no rules is refused', () async {
      final manifest = await verified(text(rulesVersion: null));
      expect(
        () => manifest.requireCompatible(
          currentRulesVersion: null,
          appVersion: '1.0.0',
        ),
        refused('no rules'),
      );
    });

    test('an unreadable version fails closed', () async {
      final manifest = await verified(text(rulesVersion: 'garbage'));
      expect(
        () => manifest.requireCompatible(
          currentRulesVersion: '1.0.0',
          appVersion: '1.0.0',
        ),
        refused('needs rules'),
      );
    });

    test('a catalog schema this build cannot read is refused', () async {
      final manifest = await verified(text(catalogSchema: '3.0.0'));
      expect(
        () => manifest.requireCompatible(
          currentRulesVersion: '1.0.15',
          appVersion: '1.0.0',
        ),
        throwsA(anything),
      );
    });

    test('a rules schema this build cannot read is refused', () async {
      final manifest = await verified(text(rulesSchema: '5.0.0'));
      expect(
        () => manifest.requireCompatible(
          currentRulesVersion: '1.0.15',
          appVersion: '1.0.0',
        ),
        throwsA(anything),
      );
    });

    test('a catalog needing a newer app is refused', () async {
      final manifest = await verified(text(catalogMinApp: '9.0.0'));
      expect(
        () => manifest.requireCompatible(
          currentRulesVersion: '1.0.15',
          appVersion: '1.0.0',
        ),
        throwsA(anything),
      );
    });

    test('a pair naming a version it blocks is refused', () async {
      final blockedRules = await verified(text(blockedRules: ['1.0.16']));
      expect(
        () => blockedRules.requireCompatible(
          currentRulesVersion: '1.0.15',
          appVersion: '1.0.0',
        ),
        refused('blocked'),
      );
      final blockedCatalog = await verified(
        text(blockedCatalog: ['2026.11.03.120000']),
      );
      expect(
        () => blockedCatalog.requireCompatible(
          currentRulesVersion: '1.0.15',
          appVersion: '1.0.0',
        ),
        refused('blocked'),
      );
    });
  });
}

const _pythonPublicKey =
    '8ec0368289f32dbbada878000f19fb5f2f08e9c4c9630489fd9d011138d31014';
const _pythonVector =
    r'''{"blocked_versions":{"catalog":["2026.11.02.000000"],"rules":["1.0.14"]},"catalog":{"min_app_version":"1.0.0","path":"v2026.11.03.120000/pharmaguide_core.db","schema_version":"5.3.0","sha256":"652f55016243bf1b9f1bbea46d5749ef892dbe394e46de9d66ab1aacf0b4af57","version":"2026.11.03.120000"},"format":1,"key_id":"vector-key-1","min_rules_version":"1.0.15","release_sequence":42,"rules":{"min_app_version":"1.0.0","path":"rules/1.0.16/interaction_db.sqlite","schema_version":"4.0.0","sha256":"6c621d1a05138a7888d37d9269a9da8e2e11e4aced2f6cfd24b05ab1b9e61bb0","version":"1.0.16"}}''';
const _pythonSignature =
    'vector-key-1:Hjk2pCMD50dxcq72BBmWEjeZ/idZxuwHUVC8rRVQDzwcWDt3aCmPb1Jgz3PGalvBALHb7g1hbvKJBixo74lCAw==';
const _pythonCatalogOnly =
    r'''{"blocked_versions":{"catalog":["2026.11.02.000000"],"rules":["1.0.14"]},"catalog":{"min_app_version":"1.0.0","path":"v2026.11.03.120000/pharmaguide_core.db","schema_version":"5.3.0","sha256":"652f55016243bf1b9f1bbea46d5749ef892dbe394e46de9d66ab1aacf0b4af57","version":"2026.11.03.120000"},"format":1,"key_id":"vector-key-1","min_rules_version":"1.0.15","release_sequence":42,"rules":null}''';
const _pythonCatalogOnlySignature =
    'vector-key-1:mIgDvhdypUq6lBFzUi46OROmrleTgGkX/sg9rk4g8ydsdtt+zqhQMjqeQ300NYfsloqo3ZAf+2ivOTnfU9iLDQ==';
