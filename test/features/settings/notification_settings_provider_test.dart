import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/settings/providers/notification_settings_provider.dart';
import 'package:pharmaguide/services/notifications/notification_authorization_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationSettingsController', () {
    for (final status in NotificationAuthorizationStatus.values) {
      test('surfaces the caption-neutral ${status.name} state', () async {
        final service = _FakeAuthorizationService(readResults: [status]);
        final lifecycle = _FakeLifecycleBinding();
        final controller = NotificationSettingsController(
          service: service,
          lifecycleBinding: lifecycle,
        );
        addTearDown(controller.dispose);

        await controller.initialRefresh;

        expect(controller.status, status);
        expect(controller.isLoading, isFalse);
        expect(controller.isActionInProgress, isFalse);
      });
    }

    test('construction reads status without requesting permission', () async {
      final service = _FakeAuthorizationService();
      final controller = NotificationSettingsController(
        service: service,
        lifecycleBinding: _FakeLifecycleBinding(),
      );
      addTearDown(controller.dispose);

      await controller.initialRefresh;

      expect(service.readCount, 1);
      expect(service.requestCount, 0);
    });

    test('an explicit request calls the service exactly once', () async {
      final request = Completer<NotificationAuthorizationStatus>();
      final service = _FakeAuthorizationService(requestCompleter: request);
      final controller = NotificationSettingsController(
        service: service,
        lifecycleBinding: _FakeLifecycleBinding(),
      );
      addTearDown(controller.dispose);
      await controller.initialRefresh;

      final action = controller.requestPermission();
      await Future<void>.delayed(Duration.zero);

      expect(service.requestCount, 1);
      expect(controller.isActionInProgress, isTrue);
      request.complete(NotificationAuthorizationStatus.allowed);
      await action;
      expect(controller.status, NotificationAuthorizationStatus.allowed);
      expect(controller.isActionInProgress, isFalse);
    });

    test('ignores a duplicate request while one is in progress', () async {
      final request = Completer<NotificationAuthorizationStatus>();
      final service = _FakeAuthorizationService(requestCompleter: request);
      final controller = NotificationSettingsController(
        service: service,
        lifecycleBinding: _FakeLifecycleBinding(),
      );
      addTearDown(controller.dispose);
      await controller.initialRefresh;

      final first = controller.requestPermission();
      final duplicate = controller.requestPermission();
      await Future<void>.delayed(Duration.zero);

      expect(service.requestCount, 1);
      request.complete(NotificationAuthorizationStatus.blocked);
      await Future.wait([first, duplicate]);
    });

    test('opens notification settings and exposes action state', () async {
      final openSettings = Completer<void>();
      final service = _FakeAuthorizationService(
        openSettingsCompleter: openSettings,
      );
      final controller = NotificationSettingsController(
        service: service,
        lifecycleBinding: _FakeLifecycleBinding(),
      );
      addTearDown(controller.dispose);
      await controller.initialRefresh;

      final action = controller.openSettings();
      await Future<void>.delayed(Duration.zero);

      expect(service.openSettingsCount, 1);
      expect(controller.isActionInProgress, isTrue);
      openSettings.complete();
      await action;
      expect(controller.isActionInProgress, isFalse);
    });

    test(
      'normalizes read, request, and settings failures to unavailable',
      () async {
        final readController = NotificationSettingsController(
          service: _FakeAuthorizationService(readError: StateError('read')),
          lifecycleBinding: _FakeLifecycleBinding(),
        );
        addTearDown(readController.dispose);
        await readController.initialRefresh;
        expect(
          readController.status,
          NotificationAuthorizationStatus.unavailable,
        );

        final requestController = NotificationSettingsController(
          service: _FakeAuthorizationService(
            requestError: StateError('request'),
          ),
          lifecycleBinding: _FakeLifecycleBinding(),
        );
        addTearDown(requestController.dispose);
        await requestController.initialRefresh;
        await requestController.requestPermission();
        expect(
          requestController.status,
          NotificationAuthorizationStatus.unavailable,
        );

        final settingsController = NotificationSettingsController(
          service: _FakeAuthorizationService(
            openSettingsError: StateError('settings'),
          ),
          lifecycleBinding: _FakeLifecycleBinding(),
        );
        addTearDown(settingsController.dispose);
        await settingsController.initialRefresh;
        await settingsController.openSettings();
        expect(
          settingsController.status,
          NotificationAuthorizationStatus.unavailable,
        );
      },
    );

    test('refreshes when the app resumes', () async {
      final service = _FakeAuthorizationService(
        readResults: [
          NotificationAuthorizationStatus.blocked,
          NotificationAuthorizationStatus.allowed,
        ],
      );
      final controller = NotificationSettingsController(
        service: service,
        lifecycleBinding: _FakeLifecycleBinding(),
      );
      addTearDown(controller.dispose);
      await controller.initialRefresh;

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(service.readCount, 1);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(service.readCount, 2);
      expect(controller.status, NotificationAuthorizationStatus.allowed);
    });

    test('does not refresh through a pending permission prompt', () async {
      final request = Completer<NotificationAuthorizationStatus>();
      final service = _FakeAuthorizationService(requestCompleter: request);
      final controller = NotificationSettingsController(
        service: service,
        lifecycleBinding: _FakeLifecycleBinding(),
      );
      addTearDown(controller.dispose);
      await controller.initialRefresh;

      final action = controller.requestPermission();
      await Future<void>.delayed(Duration.zero);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      request.complete(NotificationAuthorizationStatus.allowed);
      await action;

      expect(service.readCount, 1);
      expect(controller.status, NotificationAuthorizationStatus.allowed);
      expect(controller.isActionInProgress, isFalse);
    });

    test('registers and removes its lifecycle observer', () async {
      final lifecycle = _FakeLifecycleBinding();
      final controller = NotificationSettingsController(
        service: _FakeAuthorizationService(),
        lifecycleBinding: lifecycle,
      );
      await controller.initialRefresh;

      expect(lifecycle.added, [controller]);

      controller.dispose();

      expect(lifecycle.removed, [controller]);
    });
  });

  test('provider uses an injected authorization service', () async {
    final service = _FakeAuthorizationService(
      readResults: [NotificationAuthorizationStatus.restricted],
    );
    final container = ProviderContainer(
      overrides: [
        notificationAuthorizationServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(notificationSettingsControllerProvider);
    await controller.initialRefresh;

    expect(controller.status, NotificationAuthorizationStatus.restricted);
    expect(service.readCount, 1);
    expect(service.requestCount, 0);
  });
}

class _FakeAuthorizationService implements NotificationAuthorizationService {
  _FakeAuthorizationService({
    List<NotificationAuthorizationStatus>? readResults,
    this.requestCompleter,
    this.openSettingsCompleter,
    this.readError,
    this.requestError,
    this.openSettingsError,
  }) : readResults =
           readResults ?? [NotificationAuthorizationStatus.notDetermined];

  final List<NotificationAuthorizationStatus> readResults;
  final Completer<NotificationAuthorizationStatus>? requestCompleter;
  final Completer<void>? openSettingsCompleter;
  final Object? readError;
  final Object? requestError;
  final Object? openSettingsError;

  int readCount = 0;
  int requestCount = 0;
  int openSettingsCount = 0;

  @override
  Future<NotificationAuthorizationStatus> readStatus() async {
    readCount++;
    if (readError case final error?) throw error;
    return readResults.removeAt(0);
  }

  @override
  Future<NotificationAuthorizationStatus> requestPermission() async {
    requestCount++;
    if (requestError case final error?) throw error;
    return requestCompleter?.future ?? NotificationAuthorizationStatus.allowed;
  }

  @override
  Future<void> openNotificationSettings() async {
    openSettingsCount++;
    if (openSettingsError case final error?) throw error;
    await openSettingsCompleter?.future;
  }
}

class _FakeLifecycleBinding implements NotificationLifecycleBinding {
  final List<WidgetsBindingObserver> added = [];
  final List<WidgetsBindingObserver> removed = [];

  @override
  void addObserver(WidgetsBindingObserver observer) => added.add(observer);

  @override
  void removeObserver(WidgetsBindingObserver observer) => removed.add(observer);
}
