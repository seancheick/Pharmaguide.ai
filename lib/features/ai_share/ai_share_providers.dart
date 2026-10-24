import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/ai_share/ai_connections_repository.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';
import 'package:pharmaguide/services/sharing/ai_share_prefs_store.dart';
import 'package:pharmaguide/services/sharing/ai_share_snapshot_client.dart';

/// The only client that uploads an AI-share snapshot (ADR-009).
final aiShareSnapshotClientProvider = Provider<AiShareSnapshotClient>(
  (ref) => AiShareSnapshotClient.production(),
);

/// Device-only record of what was shared per connection and the opt-in.
final aiSharePrefsStoreProvider = Provider<AiSharePrefsStore>(
  (ref) => AiSharePrefsStore(SharedPreferencesAsyncAppPreferencesStore()),
);

final aiConnectionsRepositoryProvider = Provider<AiConnectionsRepository>(
  (ref) => SupabaseAiConnectionsRepository(),
);

/// The signed-in user's assistant connections, newest first.
final aiConnectionsProvider = FutureProvider.autoDispose<List<AiConnection>>(
  (ref) => ref.watch(aiConnectionsRepositoryProvider).listMine(),
);

/// Per-connection device-only preferences, re-read after every change.
final aiShareConnectionPrefsProvider =
    FutureProvider.autoDispose<Map<String, AiShareConnectionPrefs>>(
      (ref) => ref.watch(aiSharePrefsStoreProvider).readAll(),
    );

/// Enables only the phone-approval entry, never personal reads or snapshots.
final aiPairingEnabledProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment(
    'PHARMAGUIDE_AI_PAIRING_ENABLED',
    defaultValue: true,
  ),
);

/// Existing server barrier keeps provider cleanup retryable after relaunch.
final aiPendingRevocationProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(aiConnectionsRepositoryProvider).pendingRevocation(),
);
