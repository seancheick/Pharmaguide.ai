import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/features/settings/providers/app_preferences_provider.dart';
import 'package:pharmaguide/features/settings/providers/notification_settings_provider.dart';
import 'package:pharmaguide/features/settings/v2/notification_settings_sheet.dart';
import 'package:pharmaguide/features/settings/v2/settings_v2_screen.dart';
import 'package:pharmaguide/features/settings/v2/theme_settings_sheet.dart';
import 'package:pharmaguide/services/notifications/notification_authorization_service.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Appearance settings', () {
    testWidgets('shows three accessible choices and applies immediately', (
      tester,
    ) async {
      final controller = _preferencesController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferencesControllerProvider.overrideWith(
              (_) => controller,
              disposeNotifier: false,
            ),
          ],
          child: const _ThemeHost(),
        ),
      );

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Follows your device'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Always use light appearance'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Always use dark appearance'), findsOneWidget);

      final semantics = tester.getSemantics(
        find.byKey(const Key('theme-system')),
      );
      expect(semantics.flagsCollection.isSelected, Tristate.isTrue);

      await tester.tap(find.byKey(const Key('theme-dark')));
      await tester.pumpAndSettle();

      expect(controller.preferences.theme, AppThemePreference.dark);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('theme-dark')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
    });

    testWidgets('rolls back and explains a failed appearance save', (
      tester,
    ) async {
      final controller = _preferencesController(store: _FailingStore());
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferencesControllerProvider.overrideWith(
              (_) => controller,
              disposeNotifier: false,
            ),
          ],
          child: const _ThemeHost(),
        ),
      );

      await tester.tap(find.byKey(const Key('theme-light')));
      await tester.pumpAndSettle();

      expect(controller.preferences.theme, AppThemePreference.system);
      expect(
        find.text('Could not save appearance. Try again.'),
        findsOneWidget,
      );
    });
  });

  group('Notification settings', () {
    test('maps every status and preference caption', () {
      const defaults = NotificationPreferences();
      expect(
        notificationSettingsCaption(
          NotificationAuthorizationStatus.notDetermined,
          defaults,
          isLoading: true,
        ),
        'Checking status…',
      );
      expect(
        notificationSettingsCaption(
          NotificationAuthorizationStatus.notDetermined,
          defaults,
        ),
        'Not enabled',
      );
      expect(
        notificationSettingsCaption(
          NotificationAuthorizationStatus.blocked,
          defaults,
        ),
        'Blocked in device settings',
      );
      expect(
        notificationSettingsCaption(
          NotificationAuthorizationStatus.restricted,
          defaults,
        ),
        'Blocked in device settings',
      );
      expect(
        notificationSettingsCaption(
          NotificationAuthorizationStatus.unavailable,
          defaults,
        ),
        'Status unavailable',
      );
      expect(
        notificationSettingsCaption(
          NotificationAuthorizationStatus.unsupported,
          defaults,
        ),
        'Unavailable on this device',
      );
      expect(
        notificationSettingsCaption(
          NotificationAuthorizationStatus.allowed,
          defaults,
        ),
        'Allowed',
      );
      expect(
        notificationSettingsCaption(
          NotificationAuthorizationStatus.allowed,
          const NotificationPreferences(remindersEnabled: false),
        ),
        'Reminders paused',
      );
      expect(
        notificationSettingsCaption(
          NotificationAuthorizationStatus.allowed,
          const NotificationPreferences(
            stackRemindersEnabled: false,
            healthHistoryRemindersEnabled: false,
          ),
        ),
        'No reminder types selected',
      );
    });

    testWidgets('opening does not prompt and Enable is the explicit request', (
      tester,
    ) async {
      final service = _FakeAuthorizationService(
        initial: NotificationAuthorizationStatus.notDetermined,
      );
      final controller = _preferencesController();
      addTearDown(controller.dispose);

      await _pumpNotificationSheet(tester, service, controller);

      expect(service.requestCount, 0);
      expect(
        find.byKey(const Key('notification-status-action')),
        findsOneWidget,
      );
      expect(find.text('Recall Alerts'), findsNothing);

      await tester.tap(find.byKey(const Key('notification-status-action')));
      await tester.pumpAndSettle();

      expect(service.requestCount, 1);
      expect(find.text('Notifications allowed'), findsOneWidget);
    });

    testWidgets('blocked state offers device settings, not another prompt', (
      tester,
    ) async {
      final service = _FakeAuthorizationService(
        initial: NotificationAuthorizationStatus.blocked,
      );
      final controller = _preferencesController();
      addTearDown(controller.dispose);

      await _pumpNotificationSheet(tester, service, controller);

      expect(find.text('Open device settings'), findsOneWidget);
      expect(find.text('Enable notifications'), findsNothing);
      await tester.tap(find.text('Open device settings'));
      await tester.pumpAndSettle();

      expect(service.openSettingsCount, 1);
      expect(service.requestCount, 0);
    });

    testWidgets('master pause retains but disables category choices', (
      tester,
    ) async {
      final service = _FakeAuthorizationService(
        initial: NotificationAuthorizationStatus.allowed,
      );
      final controller = _preferencesController();
      addTearDown(controller.dispose);

      await _pumpNotificationSheet(tester, service, controller);

      await tester.tap(find.byKey(const Key('allow-reminders-switch')));
      await tester.pumpAndSettle();

      expect(controller.preferences.notifications.remindersEnabled, isFalse);
      expect(
        controller.preferences.notifications.stackRemindersEnabled,
        isTrue,
      );
      expect(
        controller.preferences.notifications.healthHistoryRemindersEnabled,
        isTrue,
      );
      expect(
        tester
            .widget<Switch>(find.byKey(const Key('stack-reminders-switch')))
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<Switch>(
              find.byKey(const Key('health-history-reminders-switch')),
            )
            .onChanged,
        isNull,
      );
      expect(
        find.text(
          "Lock-screen reminders don't include medication names, doses, "
          'conditions, appointments, or notes.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('unsupported state disables controls and has no action', (
      tester,
    ) async {
      final service = _FakeAuthorizationService(
        initial: NotificationAuthorizationStatus.unsupported,
      );
      final controller = _preferencesController();
      addTearDown(controller.dispose);

      await _pumpNotificationSheet(tester, service, controller);

      expect(
        find.text("Notifications aren't available on this device."),
        findsOneWidget,
      );
      expect(find.text('Enable notifications'), findsNothing);
      expect(find.text('Open device settings'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(
        tester
            .widget<Switch>(find.byKey(const Key('allow-reminders-switch')))
            .onChanged,
        isNull,
      );
    });

    testWidgets('rolls back and explains a failed notification save', (
      tester,
    ) async {
      final service = _FakeAuthorizationService(
        initial: NotificationAuthorizationStatus.allowed,
      );
      final controller = _preferencesController(store: _FailingBoolStore());
      addTearDown(controller.dispose);

      await _pumpNotificationSheet(tester, service, controller);
      await tester.tap(find.byKey(const Key('allow-reminders-switch')));
      await tester.pumpAndSettle();

      expect(controller.preferences.notifications.remindersEnabled, isTrue);
      expect(
        find.text('Could not save notification settings. Try again.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('Profile captions and entry points are live inputs', (
    tester,
  ) async {
    var appearanceOpened = false;
    var notificationsOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsV2Screen(
          themeCaption: 'Dark',
          notificationCaption: 'Reminders paused',
          onOpenThemeSettings: () => appearanceOpened = true,
          onOpenNotificationSettings: () => notificationsOpened = true,
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Theme'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Reminders paused'), findsOneWidget);
    await tester.tap(find.text('Theme'));
    await tester.ensureVisible(find.text('Notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notifications'));

    expect(appearanceOpened, isTrue);
    expect(notificationsOpened, isTrue);
  });
}

class _ThemeHost extends ConsumerWidget {
  const _ThemeHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref
        .watch(appPreferencesControllerProvider)
        .preferences
        .theme;
    return MaterialApp(
      theme: V2Theme.light,
      darkTheme: V2Theme.dark,
      themeMode: preference.themeMode,
      home: const Scaffold(body: ThemeSettingsSheet()),
    );
  }
}

Future<void> _pumpNotificationSheet(
  WidgetTester tester,
  _FakeAuthorizationService service,
  AppPreferencesController preferences,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appPreferencesControllerProvider.overrideWith(
          (_) => preferences,
          disposeNotifier: false,
        ),
        notificationAuthorizationServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        theme: V2Theme.light,
        darkTheme: V2Theme.dark,
        home: const Scaffold(body: NotificationSettingsSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppPreferencesController _preferencesController({AppPreferencesStore? store}) {
  return AppPreferencesController(
    repository: AppPreferencesRepository(store ?? _MemoryStore()),
  );
}

class _MemoryStore implements AppPreferencesStore {
  final Map<String, Object> values = {};

  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;

  @override
  Future<void> setString(String key, String value) async => values[key] = value;
}

class _FailingStore extends _MemoryStore {
  @override
  Future<void> setString(String key, String value) async {
    throw StateError('write failed');
  }
}

class _FailingBoolStore extends _MemoryStore {
  @override
  Future<void> setBool(String key, bool value) async {
    throw StateError('write failed');
  }
}

class _FakeAuthorizationService implements NotificationAuthorizationService {
  _FakeAuthorizationService({required this.initial});

  NotificationAuthorizationStatus initial;
  int requestCount = 0;
  int openSettingsCount = 0;

  @override
  Future<NotificationAuthorizationStatus> readStatus() async => initial;

  @override
  Future<NotificationAuthorizationStatus> requestPermission() async {
    requestCount++;
    return initial = NotificationAuthorizationStatus.allowed;
  }

  @override
  Future<void> openNotificationSettings() async {
    openSettingsCount++;
  }
}
