import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/notifications/notification_authorization_service.dart';

void main() {
  group('FlutterNotificationAuthorizationService', () {
    test('initializes without automatic Darwin permission requests', () async {
      final gateway = _FakeGateway(androidEnabled: true);
      final service = _service(
        gateway: gateway,
        platform: TargetPlatform.android,
      );

      await service.readStatus();

      final darwin = gateway.initializationSettings!.iOS!;
      expect(darwin.requestAlertPermission, isFalse);
      expect(darwin.requestBadgePermission, isFalse);
      expect(darwin.requestSoundPermission, isFalse);
      expect(darwin.requestProvisionalPermission, isFalse);
      expect(darwin.requestCriticalPermission, isFalse);
      expect(darwin.requestProvidesAppNotificationSettings, isFalse);
    });

    test('maps enabled Android notifications to allowed', () async {
      final service = _service(
        gateway: _FakeGateway(androidEnabled: true),
        platform: TargetPlatform.android,
      );

      expect(
        await service.readStatus(),
        NotificationAuthorizationStatus.allowed,
      );
    });

    test('maps first-time Android false to notDetermined', () async {
      final service = _service(
        gateway: _FakeGateway(androidEnabled: false),
        history: _FakePromptHistoryStore(wasRequested: false),
        platform: TargetPlatform.android,
      );

      expect(
        await service.readStatus(),
        NotificationAuthorizationStatus.notDetermined,
      );
    });

    test('maps previously denied Android false to blocked', () async {
      final service = _service(
        gateway: _FakeGateway(androidEnabled: false),
        history: _FakePromptHistoryStore(wasRequested: true),
        platform: TargetPlatform.android,
      );

      expect(
        await service.readStatus(),
        NotificationAuthorizationStatus.blocked,
      );
    });

    test('maps enabled iOS notifications to allowed', () async {
      final service = _service(
        gateway: _FakeGateway(iosPermissions: _iosPermissions(enabled: true)),
        platform: TargetPlatform.iOS,
      );

      expect(
        await service.readStatus(),
        NotificationAuthorizationStatus.allowed,
      );
    });

    test(
      'uses prompt history to classify disabled iOS notifications',
      () async {
        final notRequested = _service(
          gateway: _FakeGateway(
            iosPermissions: _iosPermissions(enabled: false),
          ),
          history: _FakePromptHistoryStore(wasRequested: false),
          platform: TargetPlatform.iOS,
        );
        final requested = _service(
          gateway: _FakeGateway(
            iosPermissions: _iosPermissions(enabled: false),
          ),
          history: _FakePromptHistoryStore(wasRequested: true),
          platform: TargetPlatform.iOS,
        );

        expect(
          await notRequested.readStatus(),
          NotificationAuthorizationStatus.notDetermined,
        );
        expect(
          await requested.readStatus(),
          NotificationAuthorizationStatus.blocked,
        );
      },
    );

    test(
      'explicit Android request records history and requests once',
      () async {
        final gateway = _FakeGateway(androidRequestResult: false);
        final history = _FakePromptHistoryStore();
        final service = _service(
          gateway: gateway,
          history: history,
          platform: TargetPlatform.android,
        );

        expect(
          await service.requestPermission(),
          NotificationAuthorizationStatus.blocked,
        );
        expect(gateway.androidRequestCount, 1);
        expect(history.markRequestedCount, 1);
        expect(history.wasRequested, isTrue);
      },
    );

    test('explicit iOS request records history and requests once', () async {
      final gateway = _FakeGateway(iosRequestResult: true);
      final history = _FakePromptHistoryStore();
      final service = _service(
        gateway: gateway,
        history: history,
        platform: TargetPlatform.iOS,
      );

      expect(
        await service.requestPermission(),
        NotificationAuthorizationStatus.allowed,
      );
      expect(gateway.iosRequestCount, 1);
      expect(gateway.lastIosRequest, (alert: true, badge: false, sound: true));
      expect(history.markRequestedCount, 1);
      expect(history.wasRequested, isTrue);
    });

    test('opens notification settings through the handoff gateway', () async {
      final gateway = _FakeGateway();
      final service = _service(
        gateway: gateway,
        platform: TargetPlatform.android,
      );

      await service.openNotificationSettings();

      expect(gateway.openSettingsCount, 1);
    });

    test(
      'normalizes plugin read and request failures to unavailable',
      () async {
        final readService = _service(
          gateway: _FakeGateway(readError: StateError('plugin read failed')),
          platform: TargetPlatform.android,
        );
        final requestService = _service(
          gateway: _FakeGateway(requestError: StateError('request failed')),
          platform: TargetPlatform.android,
        );

        expect(
          await readService.readStatus(),
          NotificationAuthorizationStatus.unavailable,
        );
        expect(
          await requestService.requestPermission(),
          NotificationAuthorizationStatus.unavailable,
        );
      },
    );

    test(
      'a thrown request does not turn a later disabled read into blocked',
      () async {
        final history = _FakePromptHistoryStore();
        final service = _service(
          gateway: _FakeGateway(
            androidEnabled: false,
            requestError: StateError('request failed'),
          ),
          history: history,
          platform: TargetPlatform.android,
        );

        expect(
          await service.requestPermission(),
          NotificationAuthorizationStatus.unavailable,
        );
        expect(history.markRequestedCount, 0);
        expect(
          await service.readStatus(),
          NotificationAuthorizationStatus.notDetermined,
        );
      },
    );

    test('retries initialization after a failed attempt', () async {
      final gateway = _FakeGateway(
        androidEnabled: true,
        initializationFailuresRemaining: 1,
      );
      final service = _service(
        gateway: gateway,
        platform: TargetPlatform.android,
      );

      expect(
        await service.readStatus(),
        NotificationAuthorizationStatus.unavailable,
      );
      expect(
        await service.readStatus(),
        NotificationAuthorizationStatus.allowed,
      );
      expect(gateway.initializationCount, 2);
    });

    test(
      'shares one successful initialization across concurrent reads',
      () async {
        final initialization = Completer<void>();
        final gateway = _FakeGateway(
          androidEnabled: true,
          initializationCompleter: initialization,
        );
        final service = _service(
          gateway: gateway,
          platform: TargetPlatform.android,
        );

        final first = service.readStatus();
        final second = service.readStatus();
        await Future<void>.delayed(Duration.zero);

        expect(gateway.initializationCount, 1);
        initialization.complete();
        expect(
          await Future.wait([first, second]),
          everyElement(NotificationAuthorizationStatus.allowed),
        );
        expect(gateway.initializationCount, 1);
      },
    );

    test('returns unavailable when a plugin result is absent', () async {
      final androidService = _service(
        gateway: _FakeGateway(),
        platform: TargetPlatform.android,
      );
      final iosService = _service(
        gateway: _FakeGateway(),
        platform: TargetPlatform.iOS,
      );

      expect(
        await androidService.readStatus(),
        NotificationAuthorizationStatus.unavailable,
      );
      expect(
        await iosService.readStatus(),
        NotificationAuthorizationStatus.unavailable,
      );
    });

    test(
      'returns unsupported without initializing on other platforms',
      () async {
        final gateway = _FakeGateway();
        final history = _FakePromptHistoryStore();
        final service = _service(
          gateway: gateway,
          history: history,
          platform: TargetPlatform.macOS,
        );

        expect(
          await service.readStatus(),
          NotificationAuthorizationStatus.unsupported,
        );
        expect(
          await service.requestPermission(),
          NotificationAuthorizationStatus.unsupported,
        );
        await service.openNotificationSettings();

        expect(gateway.initializationCount, 0);
        expect(gateway.androidRequestCount, 0);
        expect(gateway.iosRequestCount, 0);
        expect(gateway.openSettingsCount, 0);
        expect(history.markRequestedCount, 0);
      },
    );

    test('web is unsupported even with a mobile target platform', () async {
      final gateway = _FakeGateway();
      final service = _service(
        gateway: gateway,
        platform: TargetPlatform.iOS,
        isWeb: true,
      );

      expect(
        await service.readStatus(),
        NotificationAuthorizationStatus.unsupported,
      );
      expect(gateway.initializationCount, 0);
    });

    test('pins the production prompt-history key', () {
      expect(
        SharedPreferencesNotificationPromptHistoryStore.requestedKey,
        'notification_permission_requested',
      );
    });
  });
}

FlutterNotificationAuthorizationService _service({
  required NotificationAuthorizationPlatformGateway gateway,
  NotificationPromptHistoryStore? history,
  required TargetPlatform platform,
  bool isWeb = false,
}) {
  return FlutterNotificationAuthorizationService(
    gateway: gateway,
    promptHistory: history ?? _FakePromptHistoryStore(),
    platform: platform,
    isWeb: isWeb,
  );
}

NotificationsEnabledOptions _iosPermissions({required bool enabled}) {
  return NotificationsEnabledOptions(
    isEnabled: enabled,
    isSoundEnabled: enabled,
    isAlertEnabled: enabled,
    isBadgeEnabled: enabled,
    isProvisionalEnabled: false,
    isCriticalEnabled: false,
    isProvidesAppNotificationSettingsEnabled: false,
  );
}

class _FakePromptHistoryStore implements NotificationPromptHistoryStore {
  _FakePromptHistoryStore({this.wasRequested = false});

  bool wasRequested;
  int markRequestedCount = 0;

  @override
  Future<bool> wasPermissionRequested() async => wasRequested;

  @override
  Future<void> markPermissionRequested() async {
    markRequestedCount++;
    wasRequested = true;
  }
}

class _FakeGateway implements NotificationAuthorizationPlatformGateway {
  _FakeGateway({
    this.androidEnabled,
    this.androidRequestResult,
    this.iosPermissions,
    this.iosRequestResult,
    this.readError,
    this.requestError,
    this.initializationFailuresRemaining = 0,
    this.initializationCompleter,
  });

  final bool? androidEnabled;
  final bool? androidRequestResult;
  final NotificationsEnabledOptions? iosPermissions;
  final bool? iosRequestResult;
  final Object? readError;
  final Object? requestError;
  int initializationFailuresRemaining;
  final Completer<void>? initializationCompleter;

  int initializationCount = 0;
  int androidRequestCount = 0;
  int iosRequestCount = 0;
  int openSettingsCount = 0;
  InitializationSettings? initializationSettings;
  ({bool alert, bool badge, bool sound})? lastIosRequest;

  @override
  Future<void> initialize(InitializationSettings settings) async {
    initializationCount++;
    initializationSettings = settings;
    if (initializationFailuresRemaining > 0) {
      initializationFailuresRemaining--;
      throw StateError('initialization failed');
    }
    await initializationCompleter?.future;
  }

  @override
  Future<bool?> areAndroidNotificationsEnabled() async {
    if (readError case final error?) throw error;
    return androidEnabled;
  }

  @override
  Future<NotificationsEnabledOptions?> checkIosPermissions() async {
    if (readError case final error?) throw error;
    return iosPermissions;
  }

  @override
  Future<bool?> requestAndroidPermission() async {
    androidRequestCount++;
    if (requestError case final error?) throw error;
    return androidRequestResult;
  }

  @override
  Future<bool?> requestIosPermission({
    required bool alert,
    required bool badge,
    required bool sound,
  }) async {
    iosRequestCount++;
    lastIosRequest = (alert: alert, badge: badge, sound: sound);
    if (requestError case final error?) throw error;
    return iosRequestResult;
  }

  @override
  Future<void> openNotificationSettings() async {
    openSettingsCount++;
  }
}
