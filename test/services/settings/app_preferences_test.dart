import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';

void main() {
  group('AppPreferencesRepository', () {
    test(
      'loads System and all notification defaults from an empty store',
      () async {
        final repository = AppPreferencesRepository(_MemoryStore());

        final preferences = await repository.load();

        expect(
          preferences,
          const AppPreferences(
            theme: AppThemePreference.system,
            notifications: NotificationPreferences(),
          ),
        );
      },
    );

    test(
      'falls back to System for a malformed theme without losing valid notifications',
      () async {
        final store = _MemoryStore()
          ..values[AppPreferencesRepository.themeKey] = 'sepia'
          ..values[AppPreferencesRepository.remindersEnabledKey] = false
          ..values[AppPreferencesRepository.stackRemindersEnabledKey] = true
          ..values[AppPreferencesRepository.healthHistoryRemindersEnabledKey] =
              false;

        final preferences = await AppPreferencesRepository(store).load();

        expect(preferences.theme, AppThemePreference.system);
        expect(
          preferences.notifications,
          const NotificationPreferences(
            remindersEnabled: false,
            stackRemindersEnabled: true,
            healthHistoryRemindersEnabled: false,
          ),
        );
      },
    );

    test('falls back per malformed notification value', () async {
      final store = _MemoryStore()
        ..values[AppPreferencesRepository.themeKey] = 'dark'
        ..values[AppPreferencesRepository.remindersEnabledKey] = 'not-a-bool'
        ..values[AppPreferencesRepository.stackRemindersEnabledKey] = false
        ..values[AppPreferencesRepository.healthHistoryRemindersEnabledKey] =
            true;

      final preferences = await AppPreferencesRepository(store).load();

      expect(preferences.theme, AppThemePreference.dark);
      expect(
        preferences.notifications,
        const NotificationPreferences(
          remindersEnabled: true,
          stackRemindersEnabled: false,
          healthHistoryRemindersEnabled: true,
        ),
      );
    });

    test('persists stable theme wire values', () async {
      const expectedWireValues = <AppThemePreference, String>{
        AppThemePreference.system: 'system',
        AppThemePreference.light: 'light',
        AppThemePreference.dark: 'dark',
      };
      final store = _MemoryStore();
      final repository = AppPreferencesRepository(store);

      for (final entry in expectedWireValues.entries) {
        await repository.saveTheme(entry.key);
        expect(
          store.values[AppPreferencesRepository.themeKey],
          entry.value,
          reason: '${entry.key} must keep its persisted wire value',
        );
      }
    });

    for (final theme in AppThemePreference.values) {
      test('round-trips ${theme.name} and all notification fields', () async {
        final store = _MemoryStore();
        final repository = AppPreferencesRepository(store);

        await repository.saveTheme(theme);
        await repository.saveRemindersEnabled(false);
        await repository.saveStackRemindersEnabled(false);
        await repository.saveHealthHistoryRemindersEnabled(false);

        expect(
          await repository.load(),
          AppPreferences(
            theme: theme,
            notifications: const NotificationPreferences(
              remindersEnabled: false,
              stackRemindersEnabled: false,
              healthHistoryRemindersEnabled: false,
            ),
          ),
        );
      });
    }
  });

  group('AppPreferencesController', () {
    test(
      'rolls back, notifies again, and rethrows after a failed write',
      () async {
        final store = _MemoryStore()..writeError = StateError('disk full');
        final controller = AppPreferencesController(
          repository: AppPreferencesRepository(store),
          initialPreferences: const AppPreferences(
            theme: AppThemePreference.light,
          ),
        );
        final notifiedStates = <AppPreferences>[];
        controller.addListener(
          () => notifiedStates.add(controller.preferences),
        );

        await expectLater(
          controller.updateTheme(AppThemePreference.dark),
          throwsA(isA<StateError>()),
        );

        expect(controller.preferences.theme, AppThemePreference.light);
        expect(notifiedStates.map((state) => state.theme), [
          AppThemePreference.dark,
          AppThemePreference.light,
        ]);
      },
    );

    test(
      'an older failed write does not roll back a newer successful update',
      () async {
        final firstWrite = _PendingStringWrite();
        final secondWrite = _PendingStringWrite();
        final store = _MemoryStore()
          ..pendingStringWrites.addAll([firstWrite, secondWrite]);
        final controller = AppPreferencesController(
          repository: AppPreferencesRepository(store),
        );
        final notifiedThemes = <AppThemePreference>[];
        controller.addListener(
          () => notifiedThemes.add(controller.preferences.theme),
        );

        final olderUpdate = controller.updateTheme(AppThemePreference.dark);
        final olderFailure = expectLater(
          olderUpdate,
          throwsA(isA<StateError>()),
        );
        final newerUpdate = controller.updateTheme(AppThemePreference.light);

        await firstWrite.started.future;
        firstWrite.completion.completeError(StateError('older write failed'));
        await olderFailure;
        await secondWrite.started.future;
        secondWrite.completion.complete();
        await newerUpdate;

        expect(controller.preferences.theme, AppThemePreference.light);
        expect(notifiedThemes, [
          AppThemePreference.dark,
          AppThemePreference.light,
        ]);
      },
    );

    test('two failed overlapping writes restore the confirmed state', () async {
      final firstWrite = _PendingStringWrite();
      final secondWrite = _PendingStringWrite();
      final store = _MemoryStore()
        ..pendingStringWrites.addAll([firstWrite, secondWrite]);
      final controller = AppPreferencesController(
        repository: AppPreferencesRepository(store),
      );
      final notifiedThemes = <AppThemePreference>[];
      controller.addListener(
        () => notifiedThemes.add(controller.preferences.theme),
      );

      final olderFailure = expectLater(
        controller.updateTheme(AppThemePreference.dark),
        throwsA(isA<StateError>()),
      );
      final newerFailure = expectLater(
        controller.updateTheme(AppThemePreference.light),
        throwsA(isA<StateError>()),
      );

      await firstWrite.started.future;
      firstWrite.completion.completeError(StateError('dark write failed'));
      await olderFailure;
      await secondWrite.started.future;
      secondWrite.completion.completeError(StateError('light write failed'));
      await newerFailure;

      expect(controller.preferences.theme, AppThemePreference.system);
      expect(notifiedThemes, [
        AppThemePreference.dark,
        AppThemePreference.light,
        AppThemePreference.system,
      ]);
    });

    test(
      'a failed theme update does not survive a successful reminder update',
      () async {
        final themeWrite = _PendingStringWrite();
        final store = _MemoryStore()..pendingStringWrites.add(themeWrite);
        final controller = AppPreferencesController(
          repository: AppPreferencesRepository(store),
        );
        final notifiedStates = <AppPreferences>[];
        controller.addListener(
          () => notifiedStates.add(controller.preferences),
        );

        final themeFailure = expectLater(
          controller.updateTheme(AppThemePreference.dark),
          throwsA(isA<StateError>()),
        );
        final reminderUpdate = controller.updateRemindersEnabled(false);

        await themeWrite.started.future;
        themeWrite.completion.completeError(StateError('theme write failed'));
        await themeFailure;
        await reminderUpdate;

        expect(controller.preferences.theme, AppThemePreference.system);
        expect(controller.preferences.notifications.remindersEnabled, isFalse);
        expect(store.values[AppPreferencesRepository.themeKey], isNull);
        expect(
          store.values[AppPreferencesRepository.remindersEnabledKey],
          isFalse,
        );
        expect(notifiedStates, [
          const AppPreferences(theme: AppThemePreference.dark),
          const AppPreferences(
            theme: AppThemePreference.dark,
            notifications: NotificationPreferences(remindersEnabled: false),
          ),
          const AppPreferences(
            notifications: NotificationPreferences(remindersEnabled: false),
          ),
        ]);
      },
    );
  });
}

class _MemoryStore implements AppPreferencesStore {
  final Map<String, Object> values = <String, Object>{};
  final List<_PendingStringWrite> pendingStringWrites = <_PendingStringWrite>[];
  Object? writeError;

  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<void> setBool(String key, bool value) async {
    _throwWriteErrorIfPresent();
    values[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    if (pendingStringWrites.isNotEmpty) {
      final pendingWrite = pendingStringWrites.removeAt(0);
      pendingWrite.started.complete();
      await pendingWrite.completion.future;
    }
    _throwWriteErrorIfPresent();
    values[key] = value;
  }

  void _throwWriteErrorIfPresent() {
    final error = writeError;
    if (error != null) {
      throw error;
    }
  }
}

class _PendingStringWrite {
  final Completer<void> started = Completer<void>();
  final Completer<void> completion = Completer<void>();
}
