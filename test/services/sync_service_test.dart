import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';

void main() {
  group('SyncService.isUpdateAvailable', () {
    test('remote newer than local returns true', () async {
      final svc = SyncService(
        currentDbVersionFetcher: () async => '2026.05.17.204805',
      );

      expect(await svc.isUpdateAvailable('2026.05.17.171456'), isTrue);
    });

    test('remote equal to local returns false', () async {
      final svc = SyncService(
        currentDbVersionFetcher: () async => '2026.05.17.204805',
      );

      expect(await svc.isUpdateAvailable('2026.05.17.204805'), isFalse);
    });

    test('remote older than local returns false', () async {
      final svc = SyncService(
        currentDbVersionFetcher: () async => '2026.05.17.171456',
      );

      expect(
        await svc.isUpdateAvailable('2026.05.17.204805'),
        isFalse,
        reason: 'OTA must never downgrade a newer bundled catalog',
      );
    });

    test('malformed remote or local version fails closed', () async {
      final malformedRemote = SyncService(
        currentDbVersionFetcher: () async => 'latest',
      );
      expect(
        await malformedRemote.isUpdateAvailable('2026.05.17.204805'),
        isFalse,
      );

      final malformedLocal = SyncService(
        currentDbVersionFetcher: () async => '2026.05.17.204805',
      );
      expect(await malformedLocal.isUpdateAvailable('local-dev'), isFalse);
    });
  });
}
