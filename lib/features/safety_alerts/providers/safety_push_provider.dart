import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/services/notifications/safety_push_service.dart';

/// Starts the optional FCM transport once per app scope. The feed remains
/// usable without Firebase configuration or OS notification permission.
final safetyPushBootstrapProvider = FutureProvider<bool>((ref) async {
  final service = SafetyPushService();
  ref.onDispose(() => service.dispose());
  return service.initialize(onSafetyAlert: () {
    ref.invalidate(safetyAlertMatchesProvider);
  });
});
