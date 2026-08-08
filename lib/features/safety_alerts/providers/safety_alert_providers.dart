import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';

final safetyAlertRepositoryProvider = Provider<SafetyAlertRepository>((ref) {
  return SafetyAlertRepository();
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
final safetyAlertMatchesProvider = FutureProvider<SafetyAlertMatchSet>((ref) async {
  final stack = await ref.watch(activeStackProvider.future);
  final release = await ref.read(safetyAlertRepositoryProvider).loadCurrent();
  final matches = <({SafetyAlert alert, String dsldId})>[];
  final baseline = <String>{};
  for (final item in stack) {
    final dsldId = item.dsldId;
    if (dsldId == null || dsldId.isEmpty) continue;
    final ingredients = _ingredientIds(item.ingredientKeys);
    for (final alert in release.alerts) {
      if (!alert.appliesTo(dsldId: dsldId, ingredientCanonicalIds: ingredients)) continue;
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
    isComplete: release.isComplete,
  );
});

Set<String> _ingredientIds(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const {};
    return decoded.whereType<String>().where((id) => id.trim().isNotEmpty).toSet();
  } on Object {
    return const {};
  }
}

String _signalKey(String alertId, String dsldId) => '$alertId:$dsldId';
