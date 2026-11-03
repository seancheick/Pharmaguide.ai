import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/utils/product_canonical_ids.dart'
    as canonical_ids;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/medication_identity_providers.dart';
import 'package:pharmaguide/services/connectivity_service.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';

final safetyAlertRepositoryProvider = Provider<SafetyAlertRepository>((ref) {
  return SafetyAlertRepository();
});

/// Medications and profile, read from this device only, for matching rules.
/// A part that can't be read leaves the rest usable and marks this incomplete:
/// a recall must still show, and a missing profile must not read as an all-clear.
final deviceSafetyProfileProvider = FutureProvider<DeviceSafetyProfile>((
  ref,
) async {
  var isComplete = true;
  Future<Set<String>> read(Future<Iterable<String>> part) async {
    try {
      return (await part).toSet();
    } on Object {
      isComplete = false;
      return const {};
    }
  }

  final medicationIds = await read(
    ref.watch(localMedicationIdentityProvider.future).then((identity) {
      if (!identity.isComplete) isComplete = false;
      return identity.ids;
    }),
  );
  final conditions = await read(
    ref
        .watch(loadedProfileProvider.future)
        .then((profile) => profile.conditionsForEvaluator),
  );
  final profileFlags = await read(
    ref.watch(evaluatorProfileFlagsProvider.future),
  );
  return DeviceSafetyProfile(
    medicationIds: medicationIds,
    conditions: conditions,
    profileFlags: profileFlags,
    isComplete: isComplete,
  );
});

final class SafetyAlertMatchSet {
  const SafetyAlertMatchSet({
    required this.matches,
    required this.baselineSignalKeys,
    required this.isComplete,
  });

  final List<({SafetyAlert alert, String dsldId})> matches;
  final Set<String> baselineSignalKeys;
  final bool isComplete;
}

/// The device performs the authoritative product match. Supabase only stores
/// a frozen target set for generic push fan-out; no ingredient or health data
/// is sent back during this calculation.
final safetyAlertMatchesProvider = FutureProvider<SafetyAlertMatchSet>((
  ref,
) async {
  final stack = await ref.watch(activeStackProvider.future);
  final device = await ref.watch(deviceSafetyProfileProvider.future);
  final release = await ref.read(safetyAlertRepositoryProvider).loadCurrent();
  final matches = <({SafetyAlert alert, String dsldId})>[];
  final baseline = <String>{};
  for (final item in stack) {
    final dsldId = item.dsldId;
    if (dsldId == null || dsldId.isEmpty) continue;
    final ingredients = _ingredientIds(item.ingredientKeys);
    for (final alert in release.alerts) {
      if (!alert.appliesTo(
        dsldId: dsldId,
        ingredientCanonicalIds: ingredients,
        device: device,
      )) {
        continue;
      }
      matches.add((alert: alert, dsldId: dsldId));
      final knownRevision = release.baselineRevisions[alert.alertId];
      if (knownRevision != null && alert.revision <= knownRevision) {
        baseline.add(_signalKey(alert.alertId, dsldId));
      }
    }
  }
  return SafetyAlertMatchSet(
    matches: List.unmodifiable(matches),
    baselineSignalKeys: Set.unmodifiable(baseline),
    isComplete: release.isComplete && device.isComplete,
  );
});

/// Live alerts that match one catalog product, by exact product id or exact
/// canonical ingredient id (the same [SafetyAlert.appliesTo] match Stack
/// uses). Current verified release first, else the last verified copy on the
/// device.
final productSafetyAlertsProvider = FutureProvider.autoDispose
    .family<List<SafetyAlert>, ProductsCoreData>((ref, product) async {
      final device = await ref.watch(deviceSafetyProfileProvider.future);
      return _matching(
        await ref.read(safetyAlertRepositoryProvider).loadCurrent(),
        product,
        device,
      );
    });

List<SafetyAlert> _matching(
  SafetyAlertRelease release,
  ProductsCoreData product,
  DeviceSafetyProfile device,
) {
  final ingredientIds = canonical_ids.canonicalIdsForProduct(product);
  return release.alerts
      .where(
        (alert) => alert.appliesTo(
          dsldId: product.dsldId,
          ingredientCanonicalIds: ingredientIds,
          device: device,
        ),
      )
      .toList(growable: false);
}

/// Re-fetches the verified feed and everything computed from it.
void refreshSafetyAlerts(Ref ref) {
  ref.invalidate(safetyAlertMatchesProvider);
  ref.invalidate(productSafetyAlertsProvider);
}

/// Keeps the feed current on launch, on resume and on reconnect. Push is only a
/// supplement to this, so none of it may depend on Firebase being configured.
final safetyAlertRefreshProvider = Provider<void>((ref) {
  // Listened to directly so the launch fetch doesn't wait on, or fail with, the
  // stack analysis that also consumes it. Scans read the copy this caches.
  ref.listen(safetyAlertMatchesProvider, (_, _) {});

  final lifecycle = AppLifecycleListener(
    onResume: () => refreshSafetyAlerts(ref),
  );
  ref.onDispose(lifecycle.dispose);

  var wasOffline = false;
  ref.listen(connectionStatusProvider, (_, next) {
    switch (next.value) {
      case ConnectionStatus.offline:
        wasOffline = true;
      case ConnectionStatus.online when wasOffline:
        wasOffline = false;
        refreshSafetyAlerts(ref);
      case ConnectionStatus.online || ConnectionStatus.syncing || null:
        break;
    }
  });
});

Set<String> _ingredientIds(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const {};
    return decoded
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  } on Object {
    return const {};
  }
}

String _signalKey(String alertId, String dsldId) => '$alertId:$dsldId';
