// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track D, D2, and ADR-012.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/services/catalog_updater_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/release_manifest.dart';
import 'package:pharmaguide/services/release_store.dart';

import 'release/release_fixtures.dart';

final _shaA = 'a' * 64;
final _shaB = 'b' * 64;
final _shaC = 'c' * 64;
const _catalog = '2026.11.03.120000';

void main() {
  late ReleaseSigner signer;

  setUpAll(() async {
    await CrashReportingService().initialize();
    signer = await ReleaseSigner.create();
  });

  Future<RemoteRelease> signed({
    int sequence = 10,
    String catalogVersion = _catalog,
    String? catalogSha,
    String? rulesVersion = '1.0.16',
    String? rulesSha,
    String minRulesVersion = '1.0.15',
    List<String> blockedCatalog = const [],
    List<String> blockedRules = const [],
  }) async {
    final text = signer.manifestText(
      sequence: sequence,
      catalogVersion: catalogVersion,
      catalogSha256: catalogSha ?? _shaA,
      rulesVersion: rulesVersion,
      rulesSha256: rulesVersion == null ? null : (rulesSha ?? _shaB),
      minRulesVersion: minRulesVersion,
      blockedCatalog: blockedCatalog,
      blockedRules: blockedRules,
    );
    return RemoteRelease(
      dbVersion: catalogVersion,
      checksum: 'sha256:${catalogSha ?? _shaA}',
      signedRelease: text,
      releaseSignature: await signer.sign(text),
    );
  }

  const installed = InstalledRelease(
    sequence: 5,
    highestSequence: 5,
    catalogVersion: '2026.10.01.000000',
    rulesVersion: '1.0.15',
  );

  CatalogUpdaterService service(
    RemoteRelease? remote, {
    Map<String, String>? keys,
    List<String>? calls,
    Object? stageError,
  }) => CatalogUpdaterService(
    probeRemoteRelease: () async => remote,
    verificationKeys: keys ?? signer.keys,
    appVersion: '1.0.0',
    stageCatalog: ({required version, storagePath, expectedSha256}) async {
      if (stageError != null) throw stageError;
      calls?.add('catalog $version $storagePath $expectedSha256');
      return File('catalog.staging');
    },
    stageRules:
        ({
          required version,
          required storagePath,
          required expectedSha256,
        }) async {
          if (stageError != null) throw stageError;
          calls?.add('rules $version $storagePath $expectedSha256');
          return File('rules.staging');
        },
  );

  group('signed builds', () {
    test('a newer signed release is found', () async {
      final result = await service(
        await signed(),
      ).checkForUpdate(installed: installed);
      expect(result, isA<CatalogUpdateFound>());
      expect((result as CatalogUpdateFound).manifest!.sequence, 10);
    });

    test('the same sequence is up to date', () async {
      final result = await service(
        await signed(sequence: 5),
      ).checkForUpdate(installed: installed);
      expect(result, isA<CatalogUpToDate>());
    });

    test('an older catalog under a newer sequence is found: that is a '
        'rollback', () async {
      final result = await service(
        await signed(catalogVersion: '2026.01.01.000000'),
      ).checkForUpdate(installed: installed);
      expect(result, isA<CatalogUpdateFound>());
    });

    test('a replayed older release is refused and records nothing', () async {
      ReleaseManifest? recorded;
      final result = await service(await signed(sequence: 4)).checkForUpdate(
        installed: const InstalledRelease(
          sequence: 5,
          highestSequence: 5,
          catalogVersion: '2026.10.01.000000',
          rulesVersion: '1.0.15',
        ),
        onVerified: (manifest) async => recorded = manifest,
      );
      expect(result, isA<CatalogRefused>());
      expect(recorded, isNull);
    });

    test('a release older than the highest ever seen is refused, even above '
        'the active one', () async {
      final result = await service(await signed(sequence: 7)).checkForUpdate(
        installed: const InstalledRelease(
          sequence: 5,
          highestSequence: 8,
          catalogVersion: '2026.10.01.000000',
          rulesVersion: '1.0.15',
        ),
      );
      expect(result, isA<CatalogRefused>());
    });

    test('an unsigned row is refused', () async {
      final result = await service(
        const RemoteRelease(dbVersion: _catalog, checksum: null),
      ).checkForUpdate(installed: installed);
      expect(result, isA<CatalogRefused>());
    });

    test('a tampered row is refused and records nothing', () async {
      final good = await signed();
      ReleaseManifest? recorded;
      final result =
          await service(
            RemoteRelease(
              dbVersion: good.dbVersion,
              checksum: good.checksum,
              signedRelease: good.signedRelease!.replaceFirst(
                '1.0.16',
                '1.0.99',
              ),
              releaseSignature: good.releaseSignature,
            ),
          ).checkForUpdate(
            installed: installed,
            onVerified: (manifest) async => recorded = manifest,
          );
      expect(result, isA<CatalogRefused>());
      expect(recorded, isNull);
    });

    test('the signed text wins over the row beside it', () async {
      final good = await signed();
      final result = await service(
        RemoteRelease(
          dbVersion: '2099.01.01.000000',
          checksum: 'sha256:$_shaC',
          signedRelease: good.signedRelease,
          releaseSignature: good.releaseSignature,
        ),
      ).checkForUpdate(installed: installed);
      expect((result as CatalogUpdateFound).version, _catalog);
    });

    test(
      'an incompatible pair is refused, but its revocations are recorded',
      () async {
        ReleaseManifest? recorded;
        final result =
            await service(
              await signed(
                rulesVersion: '1.0.14',
                minRulesVersion: '1.0.15',
                blockedRules: ['1.0.15'],
              ),
            ).checkForUpdate(
              installed: installed,
              onVerified: (manifest) async => recorded = manifest,
            );
        expect(result, isA<CatalogRefused>());
        expect(recorded!.blockedRules, {'1.0.15'});
        expect(recorded!.sequence, 10);
      },
    );

    test('an up-to-date phone still records a new block', () async {
      ReleaseManifest? recorded;
      final result =
          await service(
            await signed(sequence: 5, blockedRules: ['1.0.15']),
          ).checkForUpdate(
            installed: installed,
            onVerified: (manifest) async => recorded = manifest,
          );
      expect(result, isA<CatalogUpToDate>());
      expect(recorded!.blockedRules, {'1.0.15'});
    });

    test('a release that failed to open here is refused before any download, '
        'and a newer one is not', () async {
      final calls = <String>[];
      final phone = InstalledRelease(
        sequence: 5,
        highestSequence: 10,
        catalogVersion: '2026.10.01.000000',
        rulesVersion: '1.0.15',
        refused: {
          ReleaseRecord.idFor(
            sequence: 10,
            catalogVersion: _catalog,
            rulesVersion: '1.0.16',
          ),
        },
      );
      final result = await service(
        await signed(),
        calls: calls,
      ).checkForUpdate(installed: phone);
      expect(result, isA<CatalogRefused>());
      expect(calls, isEmpty);

      final newer = await service(
        await signed(sequence: 11),
      ).checkForUpdate(installed: phone);
      expect(newer, isA<CatalogUpdateFound>());
    });

    test('a block on what the phone runs makes the update urgent', () async {
      final blocking = await service(
        await signed(blockedRules: ['1.0.15']),
      ).checkForUpdate(installed: installed);
      expect((blocking as CatalogUpdateFound).isUrgentFor(installed), isTrue);

      final routine = await service(
        await signed(),
      ).checkForUpdate(installed: installed);
      expect((routine as CatalogUpdateFound).isUrgentFor(installed), isFalse);
    });
  });

  group('staging', () {
    Future<CatalogCheckResult> stage(
      RemoteRelease remote,
      InstalledRelease phone, {
      required List<String> calls,
      Object? stageError,
    }) async {
      final svc = service(remote, calls: calls, stageError: stageError);
      final found = await svc.checkForUpdate(installed: phone);
      return svc.stage(found as CatalogUpdateFound, installed: phone);
    }

    test('downloads both files with their signed paths and hashes', () async {
      final calls = <String>[];
      final result = await stage(await signed(), installed, calls: calls);
      expect(calls, [
        'catalog $_catalog v$_catalog/pharmaguide_core.db $_shaA',
        'rules 1.0.16 rules/1.0.16/interaction_db.sqlite $_shaB',
      ]);
      final candidate = (result as CatalogStaged).candidate;
      expect(candidate.sequence, 10);
      expect(candidate.catalogSha256, _shaA);
      expect(candidate.rulesSha256, _shaB);
      expect(candidate.minRulesVersion, '1.0.15');
    });

    test('a rules-only release downloads only the rules', () async {
      final calls = <String>[];
      final result = await stage(
        await signed(),
        InstalledRelease(
          sequence: 5,
          highestSequence: 5,
          catalogVersion: _catalog,
          catalogSha256: _shaA,
          rulesVersion: '1.0.15',
        ),
        calls: calls,
      );
      expect(calls, hasLength(1));
      expect(calls.single, startsWith('rules '));
      expect((result as CatalogStaged).candidate.stagedCatalog, isNull);
    });

    test('a catalog-only release downloads only the catalog', () async {
      final calls = <String>[];
      final result = await stage(
        await signed(rulesVersion: null),
        installed,
        calls: calls,
      );
      expect(calls.single, startsWith('catalog '));
      expect((result as CatalogStaged).candidate.stagedRules, isNull);
    });

    test('a catalog with scores removed is never reused', () async {
      final calls = <String>[];
      await stage(
        await signed(),
        InstalledRelease(
          sequence: 5,
          highestSequence: 5,
          catalogVersion: _catalog,
          catalogSha256: _shaA,
          rulesVersion: '1.0.15',
          qualityWithheld: true,
        ),
        calls: calls,
      );
      expect(calls.first, startsWith('catalog '));
    });

    test('a failed download reports and changes nothing', () async {
      final result = await stage(
        await signed(),
        installed,
        calls: [],
        stageError: const SocketException('offline'),
      );
      expect(result, isA<CatalogStageFailed>());
    });
  });

  group('builds with no keys, which is every public build today', () {
    const remote = RemoteRelease(dbVersion: _catalog, checksum: 'sha256:abc');

    test(
      'never take remote rules, even from a validly signed release',
      () async {
        final calls = <String>[];
        final svc = service(await signed(), keys: const {}, calls: calls);
        final found = await svc.checkForUpdate(installed: installed);
        final result = await svc.stage(
          found as CatalogUpdateFound,
          installed: installed,
        );
        expect(found.manifest, isNull);
        expect(calls.single, startsWith('catalog '));
        expect((result as CatalogStaged).candidate.stagedRules, isNull);
        expect(result.candidate.rulesVersion, isNull);
      },
    );

    test('a newer db_version is found, with its row checksum', () async {
      final found = await service(
        remote,
        keys: const {},
      ).checkForUpdate(installed: installed);
      expect((found as CatalogUpdateFound).version, _catalog);
      expect(found.checksum, 'sha256:abc');
    });

    test('an equal or older db_version is up to date', () async {
      for (final version in [_catalog, '2026.01.01.000000']) {
        final result =
            await service(
              RemoteRelease(dbVersion: version, checksum: null),
              keys: const {},
            ).checkForUpdate(
              installed: const InstalledRelease(
                sequence: 0,
                highestSequence: 0,
                catalogVersion: _catalog,
                rulesVersion: '1.0.15',
              ),
            );
        expect(result, isA<CatalogUpToDate>());
      }
    });

    test('a malformed version never downloads', () async {
      final result = await service(
        const RemoteRelease(dbVersion: 'garbage', checksum: null),
        keys: const {},
      ).checkForUpdate(installed: installed);
      expect(result, isA<CatalogUnreachable>());
    });

    test('forceDownload retakes the current catalog', () async {
      final result = await service(remote, keys: const {}).checkForUpdate(
        installed: const InstalledRelease(
          sequence: 0,
          highestSequence: 0,
          catalogVersion: _catalog,
          rulesVersion: '1.0.15',
        ),
        forceDownload: true,
      );
      expect(result, isA<CatalogUpdateFound>());
    });
  });

  group('reaching the manifest', () {
    test('no row is unreachable', () async {
      final result = await service(null).checkForUpdate(installed: installed);
      expect(result, isA<CatalogUnreachable>());
    });

    test('a thrown probe is unreachable', () async {
      final svc = CatalogUpdaterService(
        probeRemoteRelease: () async => throw const SocketException('offline'),
        stageCatalog: ({required version, storagePath, expectedSha256}) =>
            throw StateError('must not download'),
        stageRules:
            ({
              required version,
              required storagePath,
              required expectedSha256,
            }) => throw StateError('must not download'),
        verificationKeys: signer.keys,
      );
      final result = await svc.checkForUpdate(installed: installed);
      expect(result, isA<CatalogUnreachable>());
    });
  });
}
