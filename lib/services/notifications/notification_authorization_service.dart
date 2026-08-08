import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NotificationAuthorizationStatus {
  notDetermined,
  allowed,
  blocked,
  restricted,
  unavailable,
  unsupported,
}

abstract interface class NotificationAuthorizationService {
  Future<NotificationAuthorizationStatus> readStatus();

  Future<NotificationAuthorizationStatus> requestPermission();

  Future<void> openNotificationSettings();
}

abstract interface class NotificationPromptHistoryStore {
  Future<bool> wasPermissionRequested();

  Future<void> markPermissionRequested();
}

class SharedPreferencesNotificationPromptHistoryStore
    implements NotificationPromptHistoryStore {
  SharedPreferencesNotificationPromptHistoryStore([
    SharedPreferencesAsync? preferences,
  ]) : _preferences = preferences ?? SharedPreferencesAsync();

  static const requestedKey = 'notification_permission_requested';

  final SharedPreferencesAsync _preferences;

  @override
  Future<bool> wasPermissionRequested() async {
    return await _preferences.getBool(requestedKey) ?? false;
  }

  @override
  Future<void> markPermissionRequested() {
    return _preferences.setBool(requestedKey, true);
  }
}

abstract interface class NotificationAuthorizationPlatformGateway {
  Future<void> initialize(InitializationSettings settings);

  Future<bool?> areAndroidNotificationsEnabled();

  Future<NotificationsEnabledOptions?> checkIosPermissions();

  Future<bool?> requestAndroidPermission();

  Future<bool?> requestIosPermission({
    required bool alert,
    required bool badge,
    required bool sound,
  });

  Future<void> openNotificationSettings();
}

class FlutterLocalNotificationsAuthorizationGateway
    implements NotificationAuthorizationPlatformGateway {
  FlutterLocalNotificationsAuthorizationGateway([
    FlutterLocalNotificationsPlugin? notifications,
  ]) : _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _notifications;

  @override
  Future<void> initialize(InitializationSettings settings) async {
    await _notifications.initialize(settings: settings);
  }

  @override
  Future<bool?> areAndroidNotificationsEnabled() {
    return _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled() ??
        Future<bool?>.value();
  }

  @override
  Future<NotificationsEnabledOptions?> checkIosPermissions() {
    return _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions() ??
        Future<NotificationsEnabledOptions?>.value();
  }

  @override
  Future<bool?> requestAndroidPermission() {
    return _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        Future<bool?>.value();
  }

  @override
  Future<bool?> requestIosPermission({
    required bool alert,
    required bool badge,
    required bool sound,
  }) {
    return _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: alert, badge: badge, sound: sound) ??
        Future<bool?>.value();
  }

  @override
  Future<void> openNotificationSettings() {
    return AppSettings.openAppSettings(type: AppSettingsType.notification);
  }
}

class FlutterNotificationAuthorizationService
    implements NotificationAuthorizationService {
  FlutterNotificationAuthorizationService({
    NotificationAuthorizationPlatformGateway? gateway,
    NotificationPromptHistoryStore? promptHistory,
    TargetPlatform? platform,
    bool? isWeb,
  }) : _gateway = gateway ?? FlutterLocalNotificationsAuthorizationGateway(),
       _promptHistory =
           promptHistory ?? SharedPreferencesNotificationPromptHistoryStore(),
       _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb ?? kIsWeb;

  static const _initializationSettings = InitializationSettings(
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

  final NotificationAuthorizationPlatformGateway _gateway;
  final NotificationPromptHistoryStore _promptHistory;
  final TargetPlatform _platform;
  final bool _isWeb;

  Future<void>? _initialization;
  int _initializationAttempt = 0;

  bool get _isSupported =>
      !_isWeb &&
      (_platform == TargetPlatform.android || _platform == TargetPlatform.iOS);

  Future<void> _ensureInitialized() {
    final initialization = _initialization;
    if (initialization != null) return initialization;

    final attempt = ++_initializationAttempt;
    return _initialization = _initialize(attempt);
  }

  Future<void> _initialize(int attempt) async {
    try {
      await Future<void>.sync(
        () => _gateway.initialize(_initializationSettings),
      );
    } on Object catch (_) {
      if (_initializationAttempt == attempt) _initialization = null;
      rethrow;
    }
  }

  @override
  Future<NotificationAuthorizationStatus> readStatus() async {
    if (!_isSupported) return NotificationAuthorizationStatus.unsupported;

    try {
      await _ensureInitialized();
      final enabled = switch (_platform) {
        TargetPlatform.android =>
          await _gateway.areAndroidNotificationsEnabled(),
        TargetPlatform.iOS => (await _gateway.checkIosPermissions())?.isEnabled,
        _ => null,
      };
      if (enabled == null) {
        return NotificationAuthorizationStatus.unavailable;
      }
      if (enabled) return NotificationAuthorizationStatus.allowed;

      return await _promptHistory.wasPermissionRequested()
          ? NotificationAuthorizationStatus.blocked
          : NotificationAuthorizationStatus.notDetermined;
    } on Object catch (_) {
      return NotificationAuthorizationStatus.unavailable;
    }
  }

  @override
  Future<NotificationAuthorizationStatus> requestPermission() async {
    if (!_isSupported) return NotificationAuthorizationStatus.unsupported;

    try {
      await _ensureInitialized();
      final allowed = switch (_platform) {
        TargetPlatform.android => await _gateway.requestAndroidPermission(),
        TargetPlatform.iOS => await _gateway.requestIosPermission(
          alert: true,
          badge: false,
          sound: true,
        ),
        _ => null,
      };
      if (allowed == null) {
        return NotificationAuthorizationStatus.unavailable;
      }
      await _promptHistory.markPermissionRequested();
      return allowed
          ? NotificationAuthorizationStatus.allowed
          : NotificationAuthorizationStatus.blocked;
    } on Object catch (_) {
      return NotificationAuthorizationStatus.unavailable;
    }
  }

  @override
  Future<void> openNotificationSettings() async {
    if (!_isSupported) return;
    await _gateway.openNotificationSettings();
  }
}
