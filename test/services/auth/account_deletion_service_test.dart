import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/auth/account_deletion_service.dart';

void main() {
  test('remote deletion succeeds before every local store is purged', () async {
    final operations = <String>[];
    final service = AccountDeletionService(
      backend: _Backend(() async => operations.add('remote')),
      localPurges: [
        () async => operations.add('database'),
        () async => operations.add('attachments'),
        () async => operations.add('preferences'),
        () async => operations.add('session'),
      ],
    );

    final result = await service.deleteAccount(confirmation: 'DELETE');

    expect(result, AccountDeletionResult.deleted);
    expect(operations, [
      'remote',
      'database',
      'attachments',
      'preferences',
      'session',
    ]);
  });

  test('remote failure preserves all local data for a safe retry', () async {
    var localPurges = 0;
    final service = AccountDeletionService(
      backend: _Backend(() async => throw StateError('network')),
      localPurges: [() async => localPurges++],
    );

    final result = await service.deleteAccount(confirmation: 'DELETE');

    expect(result, AccountDeletionResult.remoteFailed);
    expect(localPurges, 0);
  });

  test('all local purges run even when one local store fails', () async {
    final operations = <String>[];
    final service = AccountDeletionService(
      backend: _Backend(() async => operations.add('remote')),
      localPurges: [
        () async {
          operations.add('database');
          throw StateError('disk');
        },
        () async => operations.add('attachments'),
        () async => operations.add('preferences'),
        () async => operations.add('session'),
      ],
    );

    final result = await service.deleteAccount(confirmation: 'DELETE');

    expect(result, AccountDeletionResult.deletedLocalCleanupIncomplete);
    expect(operations, [
      'remote',
      'database',
      'attachments',
      'preferences',
      'session',
    ]);
  });

  test(
    'does not call backend without the exact destructive confirmation',
    () async {
      var called = false;
      final service = AccountDeletionService(
        backend: _Backend(() async => called = true),
        localPurges: const [],
      );

      final result = await service.deleteAccount(confirmation: 'delete');

      expect(result, AccountDeletionResult.confirmationRequired);
      expect(called, isFalse);
    },
  );
}

class _Backend implements AccountDeletionBackend {
  _Backend(this.callback);

  final Future<void> Function() callback;

  @override
  Future<void> deleteRemoteAccount({required String confirmation}) {
    return callback();
  }
}
