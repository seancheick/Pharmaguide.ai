import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/notifications/safety_push_service.dart';

const _settings = NotificationSettings(
  alert: AppleNotificationSetting.enabled,
  announcement: AppleNotificationSetting.notSupported,
  authorizationStatus: AuthorizationStatus.authorized,
  badge: AppleNotificationSetting.enabled,
  carPlay: AppleNotificationSetting.notSupported,
  lockScreen: AppleNotificationSetting.enabled,
  notificationCenter: AppleNotificationSetting.enabled,
  showPreviews: AppleShowPreviewSetting.always,
  timeSensitive: AppleNotificationSetting.notSupported,
  criticalAlert: AppleNotificationSetting.notSupported,
  sound: AppleNotificationSetting.enabled,
  providesAppNotificationSettings: AppleNotificationSetting.notSupported,
);

const _deniedSettings = NotificationSettings(
  alert: AppleNotificationSetting.disabled,
  announcement: AppleNotificationSetting.notSupported,
  authorizationStatus: AuthorizationStatus.denied,
  badge: AppleNotificationSetting.disabled,
  carPlay: AppleNotificationSetting.notSupported,
  lockScreen: AppleNotificationSetting.disabled,
  notificationCenter: AppleNotificationSetting.disabled,
  showPreviews: AppleShowPreviewSetting.notSupported,
  timeSensitive: AppleNotificationSetting.notSupported,
  criticalAlert: AppleNotificationSetting.notSupported,
  sound: AppleNotificationSetting.disabled,
  providesAppNotificationSettings: AppleNotificationSetting.notSupported,
);

class _FakeMessaging extends Fake implements FirebaseMessaging {
  _FakeMessaging({
    this.apnsTokenAfterPolls = 0,
    this.fcmToken,
    this.getTokenThrows = false,
    this.settings = _settings,
  });

  /// getAPNSToken() returns null until this many calls have happened.
  final int apnsTokenAfterPolls;
  final String? fcmToken;
  final bool getTokenThrows;
  final NotificationSettings settings;
  final List<String> log = <String>[];
  int _apnsPolls = 0;

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    log.add('requestPermission');
    return settings;
  }

  @override
  Future<String?> getAPNSToken() async {
    log.add('getAPNSToken');
    _apnsPolls++;
    if (_apnsPolls > apnsTokenAfterPolls) return 'apns-token';
    return null;
  }

  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async {
    log.add('getToken');
    if (getTokenThrows) {
      throw StateError('[firebase_messaging/apns-token-not-set]');
    }
    return fcmToken;
  }

  @override
  Future<void> deleteToken() async {
    log.add('deleteToken');
  }
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('acquireAndRegisterToken', () {
    test('a signed-out app does not prompt or acquire a push token', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messaging = _FakeMessaging(fcmToken: 'unused-token');
      final service = SafetyPushService(
        messaging: messaging,
        invokeFunction: (_, __) async {},
        isAuthenticated: () => false,
      );

      await service.acquireAndRegisterToken();

      expect(messaging.log, isEmpty);
    });

    test('a denied permission never acquires or registers a token', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messaging = _FakeMessaging(
        fcmToken: 'unused-token',
        settings: _deniedSettings,
      );
      final service = SafetyPushService(
        messaging: messaging,
        invokeFunction: (_, __) async {},
        isAuthenticated: () => true,
      );

      await service.acquireAndRegisterToken();

      expect(messaging.log, ['requestPermission']);
    });

    test(
      'iOS asks permission, waits for APNs, then requests the FCM token',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final messaging = _FakeMessaging(
          apnsTokenAfterPolls: 1,
          fcmToken: 't1',
        );
        final service = SafetyPushService(
          messaging: messaging,
          invokeFunction: (_, __) async {},
          isAuthenticated: () => true,
        );

        await service.acquireAndRegisterToken();

        // Firebase requires this exact order on Apple platforms: permission
        // first, an APNs token present, only then an FCM getToken() call.
        expect(messaging.log, [
          'requestPermission',
          'getAPNSToken',
          'getAPNSToken',
          'getToken',
        ]);
      },
    );

    test(
      'iOS never calls getToken while the APNs token stays missing',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final messaging = _FakeMessaging(
          apnsTokenAfterPolls: 99,
          fcmToken: 't1',
        );
        final service = SafetyPushService(
          messaging: messaging,
          invokeFunction: (_, __) async {},
          isAuthenticated: () => true,
        );

        await service.acquireAndRegisterToken();

        expect(messaging.log.first, 'requestPermission');
        expect(
          messaging.log,
          isNot(contains('getToken')),
          reason:
              'getToken throws without an APNs token; registration must '
              'defer to onTokenRefresh instead of failing the session',
        );
      },
    );

    test('a throwing getToken never escapes', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final messaging = _FakeMessaging(getTokenThrows: true);
      final service = SafetyPushService(
        messaging: messaging,
        invokeFunction: (_, __) async {},
        isAuthenticated: () => true,
      );

      await expectLater(service.acquireAndRegisterToken(), completes);
      expect(messaging.log, ['requestPermission', 'getToken']);
    });
  });

  group('unregisterBeforeSignOut', () {
    test('removes the server row, then invalidates the local token', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messaging = _FakeMessaging(fcmToken: 'live-token');
      final calls = <(String, Map<String, dynamic>)>[];
      final service = SafetyPushService(
        messaging: messaging,
        invokeFunction: (name, body) async => calls.add((name, body)),
      );

      await service.unregisterBeforeSignOut();

      expect(calls, hasLength(1));
      expect(calls.single.$1, 'register-push-token');
      expect(calls.single.$2, {'action': 'unregister', 'token': 'live-token'});
      // Local invalidation happens after the authorized server delete so the
      // row is removed by us, not left for UNREGISTERED pruning.
      expect(messaging.log.last, 'deleteToken');
    });

    test(
      'still invalidates the local token when the server call fails',
      () async {
        final messaging = _FakeMessaging(fcmToken: 'live-token');
        final service = SafetyPushService(
          messaging: messaging,
          invokeFunction: (_, __) async => throw Exception('offline'),
        );

        await expectLater(service.unregisterBeforeSignOut(), completes);
        expect(messaging.log.last, 'deleteToken');
      },
    );

    test(
      'with no readable token it skips the server call and still deletes',
      () async {
        final messaging = _FakeMessaging(getTokenThrows: true);
        final calls = <String>[];
        final service = SafetyPushService(
          messaging: messaging,
          invokeFunction: (name, _) async => calls.add(name),
        );

        await expectLater(service.unregisterBeforeSignOut(), completes);
        expect(calls, isEmpty);
        expect(messaging.log.last, 'deleteToken');
      },
    );
  });
}
