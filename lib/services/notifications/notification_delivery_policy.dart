import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/settings/providers/app_preferences_provider.dart';
import 'package:pharmaguide/features/settings/providers/notification_settings_provider.dart';
import 'package:pharmaguide/services/notifications/notification_authorization_service.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';

enum NotificationCategory {
  stackReminders,
  healthHistoryReminders,
  safetyRecallAlerts,
}

enum NotificationDeliveryAction { schedule, cancel, preserve }

const currentNotificationProducerAvailability =
    NotificationProducerAvailability(
      stackReminders: true,
      healthHistoryReminders: true,
      safetyRecallAlerts: true,
    );

final notificationProducerAvailabilityProvider =
    Provider<NotificationProducerAvailability>((ref) {
      return currentNotificationProducerAvailability;
    });

final notificationDeliveryPolicyProvider = Provider<NotificationDeliveryPolicy>(
  (ref) {
    return NotificationDeliveryPolicy(
      authorizationStatus: ref
          .watch(notificationSettingsControllerProvider)
          .status,
      preferences: ref
          .watch(appPreferencesControllerProvider)
          .preferences
          .notifications,
      producerAvailability: ref.watch(notificationProducerAvailabilityProvider),
    );
  },
);

@immutable
class NotificationProducerAvailability {
  const NotificationProducerAvailability({
    required this.stackReminders,
    required this.healthHistoryReminders,
    required this.safetyRecallAlerts,
  });

  final bool stackReminders;
  final bool healthHistoryReminders;
  final bool safetyRecallAlerts;

  bool isAvailable(NotificationCategory category) => switch (category) {
    NotificationCategory.stackReminders => stackReminders,
    NotificationCategory.healthHistoryReminders => healthHistoryReminders,
    NotificationCategory.safetyRecallAlerts => safetyRecallAlerts,
  };
}

@immutable
class NotificationDeliveryPolicy {
  const NotificationDeliveryPolicy({
    required this.authorizationStatus,
    required this.preferences,
    required this.producerAvailability,
  });

  final NotificationAuthorizationStatus authorizationStatus;
  final NotificationPreferences preferences;
  final NotificationProducerAvailability producerAvailability;

  NotificationDeliveryAction actionFor(NotificationCategory category) {
    if (!producerAvailability.isAvailable(category)) {
      return NotificationDeliveryAction.preserve;
    }

    switch (authorizationStatus) {
      case NotificationAuthorizationStatus.blocked:
      case NotificationAuthorizationStatus.restricted:
        return NotificationDeliveryAction.cancel;
      case NotificationAuthorizationStatus.unavailable:
      case NotificationAuthorizationStatus.notDetermined:
      case NotificationAuthorizationStatus.unsupported:
        return NotificationDeliveryAction.preserve;
      case NotificationAuthorizationStatus.allowed:
        break;
    }

    return switch (category) {
      NotificationCategory.safetyRecallAlerts =>
        NotificationDeliveryAction.schedule,
      NotificationCategory.stackReminders =>
        preferences.remindersEnabled && preferences.stackRemindersEnabled
            ? NotificationDeliveryAction.schedule
            : NotificationDeliveryAction.cancel,
      NotificationCategory.healthHistoryReminders =>
        preferences.remindersEnabled &&
                preferences.healthHistoryRemindersEnabled
            ? NotificationDeliveryAction.schedule
            : NotificationDeliveryAction.cancel,
    };
  }
}
