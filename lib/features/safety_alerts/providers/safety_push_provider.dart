import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/navigation/root_navigator_key.dart';
import 'package:pharmaguide/features/contributions/providers/product_submission_providers.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/features/settings/v2/product_submission_status_sheet.dart';
import 'package:pharmaguide/services/notifications/safety_push_service.dart';

/// Starts the optional FCM transport once per app scope. The feed remains
/// usable without Firebase configuration or OS notification permission.
final safetyPushBootstrapProvider = FutureProvider<bool>((ref) async {
  final service = SafetyPushService();
  ref.onDispose(() => service.dispose());
  return service.initialize(
    onSafetyAlert: () {
      ref.invalidate(safetyAlertMatchesProvider);
    },
    // Foreground: quiet data refresh (no banner shows in foreground).
    onSubmissionUpdate: () {
      ref.invalidate(productSubmissionsProvider);
    },
    // Tap-through: the user asked to see it — open the status surface.
    onSubmissionUpdateOpened: () async {
      ref.invalidate(productSubmissionsProvider);
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await showProductSubmissionStatusSheet(context);
    },
  );
});
