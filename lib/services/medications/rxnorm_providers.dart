// Riverpod providers for the RxNorm medication-entry stack (M4 §8.4-§8.5).
//
// We expose [RxNormApiService] as a Provider that wires the production
// transport (`defaultRxNormHttpGet`) and the bundled offline DB. Tests
// override this provider with a fake-transport service that returns
// canned JSON; we never want a real HTTP call from a widget test.
//
// Why a single provider for the service (instead of one provider per
// RPC):
//   - The service owns the LRU cache and rate-limit window. Splitting
//     it would defeat both — every consumer would get its own cache
//     and the throttle would never coalesce across screens.
//   - Riverpod auto-disposes the provider when the widget tree no
//     longer references it; the cache evicts naturally.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/services/medications/rxnorm_api_service.dart';

/// Singleton-per-app [RxNormApiService]. Construction is cheap (no
/// I/O) so we let Riverpod recreate it if the bundled InteractionDb
/// gets re-opened — the cost is just discarding the LRU.
final rxNormApiServiceProvider = Provider<RxNormApiService>((ref) {
  final interactionDb = ref.watch(interactionDatabaseProvider);
  return RxNormApiService(offlineDb: interactionDb);
});
