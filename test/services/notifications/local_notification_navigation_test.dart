import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/navigation/launch_link_buffer.dart';
import 'package:pharmaguide/core/navigation/root_navigator_key.dart';
import 'package:pharmaguide/features/stack/providers/stack_reminder_providers.dart';
import 'package:pharmaguide/services/history/local_health_reminder_service.dart';
import 'package:pharmaguide/services/notifications/local_notification_navigation.dart';
import 'package:pharmaguide/services/notifications/notification_authorization_service.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');
const _tap = {
  'notificationResponseType': 0,
  'id': 100,
  'payload': 'stack-reminder',
};

Future<void> _deliver(
  WidgetTester tester,
  Map<String, Object?> response,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _channel.name,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('didReceiveNotificationResponse', response),
    ),
    (_) {},
  );
  await tester.pump();
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (_) async => 'America/New_York',
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          null,
        );
  });
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '$platform pill tap is retained during startup, including after other clients initialize',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        if (platform == TargetPlatform.iOS) {
          IOSFlutterLocalNotificationsPlugin.registerWith();
        } else {
          AndroidFlutterLocalNotificationsPlugin.registerWith();
        }
        final buffer = LaunchLinkBuffer()..attach();
        final container = ProviderContainer();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          (call) async =>
              call.method == 'pendingNotificationRequests' ? [] : true,
        );
        try {
          await tester.pumpWidget(const MaterialApp(home: Text('Preparing')));
          await FlutterLocalNotificationsAuthorizationGateway().initialize(
            localNotificationInitializationSettings,
          );
          await _deliver(tester, _tap);
          expect(buffer.takeLocation(), Routes.stack);
          // Both schedulers share the platform plugin. Neither may remove the
          // tap callback by initializing it without a response handler.
          await tester.runAsync(
            () => container.read(stackReminderSchedulerProvider).cancelOwned(),
          );
          await _deliver(tester, _tap);
          expect(buffer.takeLocation(), Routes.stack);
          await tester.runAsync(
            () => LocalHealthReminderService().cancelOwned(),
          );
          await _deliver(tester, _tap);
          expect(buffer.takeLocation(), Routes.stack);
        } finally {
          buffer.detach();
          container.dispose();
          debugDefaultTargetPlatformOverride = null;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            _channel,
            null,
          );
        }
      },
    );

    testWidgets(
      '$platform notification launch opens Stack without replay on later initialization',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        if (platform == TargetPlatform.iOS) {
          IOSFlutterLocalNotificationsPlugin.registerWith();
        } else {
          AndroidFlutterLocalNotificationsPlugin.registerWith();
        }
        final buffer = LaunchLinkBuffer()..attach();
        var launchReads = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          (call) async {
            if (call.method == 'getNotificationAppLaunchDetails') {
              launchReads++;
              return {
                'notificationLaunchedApp': true,
                'notificationResponse': {..._tap, 'notificationId': 100},
              };
            }
            return true;
          },
        );
        try {
          await tester.pumpWidget(const MaterialApp(home: Text('Preparing')));
          await initializeLocalNotifications(
            FlutterLocalNotificationsPlugin(),
            captureLaunch: true,
          );
          expect(buffer.takeLocation(), Routes.stack);
          await FlutterLocalNotificationsAuthorizationGateway().initialize(
            localNotificationInitializationSettings,
          );
          expect(buffer.takeLocation(), isNull);
          expect(launchReads, 1);
        } finally {
          buffer.detach();
          debugDefaultTargetPlatformOverride = null;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            _channel,
            null,
          );
        }
      },
    );
  }

  testWidgets(
    'a running-app reminder tap navigates the existing router to Stack',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      final router = GoRouter(
        navigatorKey: rootNavigatorKey,
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (_, _) => const Scaffold(body: Text('Home page')),
          ),
          GoRoute(
            path: Routes.stack,
            builder: (_, _) => const Scaffold(body: Text('Stack page')),
          ),
        ],
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (_) async => true,
      );
      try {
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await FlutterLocalNotificationsAuthorizationGateway().initialize(
          localNotificationInitializationSettings,
        );
        await _deliver(tester, _tap);
        await tester.pumpAndSettle();
        expect(find.text('Stack page'), findsOneWidget);
        expect(find.text('Home page'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        debugDefaultTargetPlatformOverride = null;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        );
      }
    },
  );

  testWidgets('other payloads, actions and a normal launch do not open Stack', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    final buffer = LaunchLinkBuffer()..attach();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async => call.method == 'getNotificationAppLaunchDetails'
          ? {
              'notificationLaunchedApp': false,
              'notificationResponse': {..._tap, 'notificationId': 100},
            }
          : true,
    );
    try {
      await tester.pumpWidget(const MaterialApp(home: Text('Preparing')));
      await initializeLocalNotifications(
        FlutterLocalNotificationsPlugin(),
        captureLaunch: true,
      );
      for (final response in [
        {..._tap, 'payload': 'health-history'},
        {..._tap, 'payload': null},
        {..._tap, 'payload': '/arbitrary-path'},
        {..._tap, 'notificationResponseType': 1},
      ]) {
        await _deliver(tester, response);
      }
      expect(buffer.takeLocation(), isNull);
    } finally {
      buffer.detach();
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      );
    }
  });
}
