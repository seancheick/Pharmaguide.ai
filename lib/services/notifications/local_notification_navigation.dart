import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/navigation/launch_link_buffer.dart';

const localNotificationInitializationSettings = InitializationSettings(
  android: AndroidInitializationSettings('ic_launcher'),
  iOS: DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
    requestProvisionalPermission: false,
    requestCriticalPermission: false,
    requestProvidesAppNotificationSettings: false,
  ),
);

void handleLocalNotificationResponse(NotificationResponse response) {
  if (response.notificationResponseType ==
          NotificationResponseType.selectedNotification &&
      response.payload == 'stack-reminder') {
    LaunchLinkBuffer.openLocation(Routes.stack);
  }
}

/// Every client initializes the same plugin singleton. Always retain its tap
/// callback when another reminder client or the permission gateway initializes.
Future<void> initializeLocalNotifications(
  FlutterLocalNotificationsPlugin notifications, {
  InitializationSettings settings = localNotificationInitializationSettings,
  bool captureLaunch = false,
}) async {
  await notifications.initialize(
    settings: settings,
    onDidReceiveNotificationResponse: handleLocalNotificationResponse,
  );
  // A tap that starts a terminated app is returned here rather than through
  // the running-app callback. Only bootstrap consumes this launch response.
  if (captureLaunch) {
    final launch = await notifications.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true && response != null) {
      handleLocalNotificationResponse(response);
    }
  }
}
