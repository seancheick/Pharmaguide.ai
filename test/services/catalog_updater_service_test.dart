// Spec: INITIATIVE_STACK_INTELLIGENCE.md, Track D, D2.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/catalog_updater_service.dart';

void main() {
  group('CatalogUpdaterService.checkForUpdate', () {
    test('newer remote version → CatalogStaged', () async {
      var stageCalls = 0;
      String? stagePassedExpected;
      final svc = CatalogUpdaterService(
        probeRemoteVersion: () async => '2026.04.28.013000',
        stageDownload: ({String? expectedVersion}) async {
          stageCalls++;
          stagePassedExpected = expectedVersion;
          return '2026.04.28.013000';
        },
      );

      final result = await svc.checkForUpdate(
        installedVersion: '2026.04.27.063145',
      );

      expect(result, isA<CatalogStaged>());
      expect((result as CatalogStaged).version, '2026.04.28.013000');
      expect(stageCalls, 1);
      expect(
        stagePassedExpected,
        '2026.04.28.013000',
        reason:
            'service must pin the version it just probed so the '
            'staged file is exactly what the manifest advertised',
      );
    });

    test('remote == installed → CatalogUpToDate, no download fired', () async {
      var stageCalls = 0;
      final svc = CatalogUpdaterService(
        probeRemoteVersion: () async => '2026.04.27.063145',
        stageDownload: ({String? expectedVersion}) async {
          stageCalls++;
          return 'should-never-be-returned';
        },
      );

      final result = await svc.checkForUpdate(
        installedVersion: '2026.04.27.063145',
      );

      expect(result, isA<CatalogUpToDate>());
      expect((result as CatalogUpToDate).version, '2026.04.27.063145');
      expect(
        stageCalls,
        0,
        reason: 'a same-version no-op must not touch the network',
      );
    });

    test(
      'remote older than installed → CatalogUpToDate, no download fired',
      () async {
        var stageCalls = 0;
        final svc = CatalogUpdaterService(
          probeRemoteVersion: () async => '2026.05.17.171456',
          stageDownload: ({String? expectedVersion}) async {
            stageCalls++;
            return 'should-never-be-returned';
          },
        );

        final result = await svc.checkForUpdate(
          installedVersion: '2026.05.17.204805',
        );

        expect(result, isA<CatalogUpToDate>());
        expect((result as CatalogUpToDate).version, '2026.05.17.204805');
        expect(
          stageCalls,
          0,
          reason: 'a stale remote catalog must not be staged as an update',
        );
      },
    );

    test('malformed remote or installed version fails closed', () async {
      var stageCalls = 0;
      final malformedRemote = CatalogUpdaterService(
        probeRemoteVersion: () async => 'current',
        stageDownload: ({String? expectedVersion}) async {
          stageCalls++;
          return 'should-never-be-returned';
        },
      );

      final remoteResult = await malformedRemote.checkForUpdate(
        installedVersion: '2026.05.17.204805',
      );
      expect(remoteResult, isA<CatalogUnreachable>());
      expect(stageCalls, 0);

      final malformedInstalled = CatalogUpdaterService(
        probeRemoteVersion: () async => '2026.05.17.204805',
        stageDownload: ({String? expectedVersion}) async {
          stageCalls++;
          return 'should-never-be-returned';
        },
      );

      final installedResult = await malformedInstalled.checkForUpdate(
        installedVersion: 'local-dev',
      );
      expect(installedResult, isA<CatalogUnreachable>());
      expect(stageCalls, 0);
    });

    test('forceDownload bypasses the version-match short-circuit', () async {
      var stageCalls = 0;
      final svc = CatalogUpdaterService(
        probeRemoteVersion: () async => '2026.04.27.063145',
        stageDownload: ({String? expectedVersion}) async {
          stageCalls++;
          return '2026.04.27.063145';
        },
      );

      final result = await svc.checkForUpdate(
        installedVersion: '2026.04.27.063145',
        forceDownload: true,
      );

      expect(result, isA<CatalogStaged>());
      expect((result as CatalogStaged).version, '2026.04.27.063145');
      expect(stageCalls, 1);
    });

    test(
      'first launch (installedVersion=null) always stages the remote',
      () async {
        var stageCalls = 0;
        final svc = CatalogUpdaterService(
          probeRemoteVersion: () async => '2026.04.27.063145',
          stageDownload: ({String? expectedVersion}) async {
            stageCalls++;
            return '2026.04.27.063145';
          },
        );

        final result = await svc.checkForUpdate();

        expect(result, isA<CatalogStaged>());
        expect(stageCalls, 1);
      },
    );

    test('probe throws → CatalogUnreachable, no download fired', () async {
      var stageCalls = 0;
      final svc = CatalogUpdaterService(
        probeRemoteVersion: () async {
          throw Exception('network down');
        },
        stageDownload: ({String? expectedVersion}) async {
          stageCalls++;
          return 'unused';
        },
      );

      final result = await svc.checkForUpdate(
        installedVersion: '2026.04.27.063145',
      );

      expect(result, isA<CatalogUnreachable>());
      expect((result as CatalogUnreachable).error, isA<Exception>());
      expect(stageCalls, 0);
    });

    test(
      'probe returns null → CatalogUnreachable (table empty / first push)',
      () async {
        var stageCalls = 0;
        final svc = CatalogUpdaterService(
          probeRemoteVersion: () async => null,
          stageDownload: ({String? expectedVersion}) async {
            stageCalls++;
            return 'unused';
          },
        );

        final result = await svc.checkForUpdate(
          installedVersion: '2026.04.27.063145',
        );

        expect(result, isA<CatalogUnreachable>());
        expect(
          (result as CatalogUnreachable).error,
          isNull,
          reason:
              'a null probe is a soft "no manifest" — there is no '
              'underlying error to attach',
        );
        expect(stageCalls, 0);
      },
    );

    test(
      'stage fails (network drop / sha mismatch) → CatalogStageFailed',
      () async {
        final svc = CatalogUpdaterService(
          probeRemoteVersion: () async => '2026.04.28.013000',
          stageDownload: ({String? expectedVersion}) async {
            throw StateError('SHA-256 mismatch on staged bundle');
          },
        );

        final result = await svc.checkForUpdate(
          installedVersion: '2026.04.27.063145',
        );

        expect(result, isA<CatalogStageFailed>());
        final failed = result as CatalogStageFailed;
        expect(failed.error, isA<StateError>());
        expect(failed.reason, contains('stageCoreDbDownload'));
        expect(failed.reason, contains('SHA-256 mismatch'));
      },
    );

    test('production factory constructs without crashing', () {
      // Smoke test only — wiring the real SyncService here would
      // require a Supabase client + path_provider, which are out of
      // scope for a pure-Dart unit test. The factory should at least
      // be callable so a typo in the wiring fails the suite, not the
      // app at runtime.
      expect(() => CatalogUpdaterService.production, returnsNormally);
    });
  });
}
