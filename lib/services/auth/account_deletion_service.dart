import 'package:supabase_flutter/supabase_flutter.dart';

enum AccountDeletionResult {
  deleted,
  confirmationRequired,
  remoteFailed,
  deletedLocalCleanupIncomplete,
}

abstract interface class AccountDeletionBackend {
  Future<void> deleteRemoteAccount({required String confirmation});
}

/// Coordinates irreversible account deletion without leaving private Storage
/// objects or skipping local stores after the server account is gone.
///
/// The backend owns remote ordering: remove Storage objects first, then delete
/// the Auth user so database cascades can safely remove manifests. Local purge
/// steps run only after that transaction boundary succeeds.
class AccountDeletionService {
  const AccountDeletionService({
    required this.backend,
    required this.localPurges,
  });

  final AccountDeletionBackend backend;
  final List<Future<void> Function()> localPurges;

  factory AccountDeletionService.production({
    SupabaseClient? client,
    required List<Future<void> Function()> localPurges,
  }) {
    return AccountDeletionService(
      backend: _SupabaseAccountDeletionBackend(
        client ?? Supabase.instance.client,
      ),
      localPurges: localPurges,
    );
  }

  Future<AccountDeletionResult> deleteAccount({
    required String confirmation,
  }) async {
    if (confirmation != 'DELETE') {
      return AccountDeletionResult.confirmationRequired;
    }

    try {
      await backend.deleteRemoteAccount(confirmation: confirmation);
    } on Object {
      return AccountDeletionResult.remoteFailed;
    }

    var localCleanupFailed = false;
    for (final purge in localPurges) {
      try {
        await purge();
      } on Object {
        // Continue through every independent local store. Once the remote
        // account is deleted, stopping after the first local error would leave
        // more recoverable user data on the device.
        localCleanupFailed = true;
      }
    }
    return localCleanupFailed
        ? AccountDeletionResult.deletedLocalCleanupIncomplete
        : AccountDeletionResult.deleted;
  }
}

class _SupabaseAccountDeletionBackend implements AccountDeletionBackend {
  const _SupabaseAccountDeletionBackend(this._client);

  final SupabaseClient _client;

  @override
  Future<void> deleteRemoteAccount({required String confirmation}) async {
    final response = await _client.functions.invoke(
      'delete-account',
      body: {'confirmation': confirmation},
    );
    final data = response.data;
    final deleted =
        data is Map && data['deleted'] == true && response.status == 200;
    if (!deleted) {
      throw StateError('Remote account deletion did not confirm success.');
    }
  }
}
