import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { system, light, dark }

@immutable
class NotificationPreferences {
  const NotificationPreferences({
    this.remindersEnabled = true,
    this.stackRemindersEnabled = true,
    this.healthHistoryRemindersEnabled = true,
  });

  final bool remindersEnabled;
  final bool stackRemindersEnabled;
  final bool healthHistoryRemindersEnabled;

  NotificationPreferences copyWith({
    bool? remindersEnabled,
    bool? stackRemindersEnabled,
    bool? healthHistoryRemindersEnabled,
  }) {
    return NotificationPreferences(
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      stackRemindersEnabled:
          stackRemindersEnabled ?? this.stackRemindersEnabled,
      healthHistoryRemindersEnabled:
          healthHistoryRemindersEnabled ?? this.healthHistoryRemindersEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is NotificationPreferences &&
            remindersEnabled == other.remindersEnabled &&
            stackRemindersEnabled == other.stackRemindersEnabled &&
            healthHistoryRemindersEnabled ==
                other.healthHistoryRemindersEnabled;
  }

  @override
  int get hashCode => Object.hash(
    remindersEnabled,
    stackRemindersEnabled,
    healthHistoryRemindersEnabled,
  );
}

@immutable
class AppPreferences {
  const AppPreferences({
    this.theme = AppThemePreference.system,
    this.notifications = const NotificationPreferences(),
  });

  final AppThemePreference theme;
  final NotificationPreferences notifications;

  AppPreferences copyWith({
    AppThemePreference? theme,
    NotificationPreferences? notifications,
  }) {
    return AppPreferences(
      theme: theme ?? this.theme,
      notifications: notifications ?? this.notifications,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppPreferences &&
            theme == other.theme &&
            notifications == other.notifications;
  }

  @override
  int get hashCode => Object.hash(theme, notifications);
}

abstract interface class AppPreferencesStore {
  Future<String?> getString(String key);

  Future<bool?> getBool(String key);

  Future<void> setString(String key, String value);

  Future<void> setBool(String key, bool value);
}

class SharedPreferencesAsyncAppPreferencesStore implements AppPreferencesStore {
  SharedPreferencesAsyncAppPreferencesStore([
    SharedPreferencesAsync? preferences,
  ]) : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<bool?> getBool(String key) => _preferences.getBool(key);

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setBool(String key, bool value) =>
      _preferences.setBool(key, value);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
}

class AppPreferencesRepository {
  AppPreferencesRepository(this._store);

  static const themeKey = 'app_theme_preference';
  static const remindersEnabledKey = 'notifications_reminders_enabled';
  static const stackRemindersEnabledKey =
      'notifications_stack_reminders_enabled';
  static const healthHistoryRemindersEnabledKey =
      'notifications_health_history_reminders_enabled';

  final AppPreferencesStore _store;

  Future<AppPreferences> load() async {
    final themeName = await _readOrDefault<String?>(
      () => _store.getString(themeKey),
      null,
    );
    final remindersEnabled = await _readOrDefault(
      () => _store.getBool(remindersEnabledKey),
      true,
    );
    final stackRemindersEnabled = await _readOrDefault(
      () => _store.getBool(stackRemindersEnabledKey),
      true,
    );
    final healthHistoryRemindersEnabled = await _readOrDefault(
      () => _store.getBool(healthHistoryRemindersEnabledKey),
      true,
    );

    return AppPreferences(
      theme: _parseTheme(themeName),
      notifications: NotificationPreferences(
        remindersEnabled: remindersEnabled,
        stackRemindersEnabled: stackRemindersEnabled,
        healthHistoryRemindersEnabled: healthHistoryRemindersEnabled,
      ),
    );
  }

  Future<void> saveTheme(AppThemePreference theme) =>
      _store.setString(themeKey, _themeWireValue(theme));

  Future<void> saveRemindersEnabled(bool enabled) =>
      _store.setBool(remindersEnabledKey, enabled);

  Future<void> saveStackRemindersEnabled(bool enabled) =>
      _store.setBool(stackRemindersEnabledKey, enabled);

  Future<void> saveHealthHistoryRemindersEnabled(bool enabled) =>
      _store.setBool(healthHistoryRemindersEnabledKey, enabled);

  static AppThemePreference _parseTheme(String? value) {
    return switch (value) {
      'system' => AppThemePreference.system,
      'light' => AppThemePreference.light,
      'dark' => AppThemePreference.dark,
      _ => AppThemePreference.system,
    };
  }

  static String _themeWireValue(AppThemePreference theme) {
    return switch (theme) {
      AppThemePreference.system => 'system',
      AppThemePreference.light => 'light',
      AppThemePreference.dark => 'dark',
    };
  }

  static Future<T> _readOrDefault<T>(
    Future<T?> Function() read,
    T defaultValue,
  ) async {
    try {
      return await read() ?? defaultValue;
    } on Object {
      return defaultValue;
    }
  }
}

class AppPreferencesController extends ChangeNotifier {
  AppPreferencesController({
    required this.repository,
    AppPreferences initialPreferences = const AppPreferences(),
  }) : _preferences = initialPreferences,
       _confirmedPreferences = initialPreferences;

  final AppPreferencesRepository repository;
  AppPreferences _preferences;
  AppPreferences _confirmedPreferences;
  final List<_PendingPreferencesUpdate> _pendingUpdates =
      <_PendingPreferencesUpdate>[];
  Future<void> _writeQueue = Future<void>.value();

  AppPreferences get preferences => _preferences;

  Future<void> updateTheme(AppThemePreference theme) {
    return _update(
      (preferences) => preferences.copyWith(theme: theme),
      () => repository.saveTheme(theme),
    );
  }

  Future<void> updateRemindersEnabled(bool enabled) {
    return _update(
      (preferences) => preferences.copyWith(
        notifications: preferences.notifications.copyWith(
          remindersEnabled: enabled,
        ),
      ),
      () => repository.saveRemindersEnabled(enabled),
    );
  }

  Future<void> updateStackRemindersEnabled(bool enabled) {
    return _update(
      (preferences) => preferences.copyWith(
        notifications: preferences.notifications.copyWith(
          stackRemindersEnabled: enabled,
        ),
      ),
      () => repository.saveStackRemindersEnabled(enabled),
    );
  }

  Future<void> updateHealthHistoryRemindersEnabled(bool enabled) {
    return _update(
      (preferences) => preferences.copyWith(
        notifications: preferences.notifications.copyWith(
          healthHistoryRemindersEnabled: enabled,
        ),
      ),
      () => repository.saveHealthHistoryRemindersEnabled(enabled),
    );
  }

  Future<void> _update(
    AppPreferences Function(AppPreferences) apply,
    Future<void> Function() persist,
  ) {
    final update = _PendingPreferencesUpdate(apply, persist);
    _pendingUpdates.add(update);
    _recomputePreferences();

    final write = _writeQueue.then((_) async {
      try {
        await update.persist();
        _confirmedPreferences = apply(_confirmedPreferences);
      } finally {
        _pendingUpdates.remove(update);
        _recomputePreferences();
      }
    });
    _writeQueue = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return write;
  }

  void _recomputePreferences() {
    var next = _confirmedPreferences;
    for (final update in _pendingUpdates) {
      next = update.apply(next);
    }
    if (next == _preferences) {
      return;
    }
    _preferences = next;
    notifyListeners();
  }
}

class _PendingPreferencesUpdate {
  _PendingPreferencesUpdate(this.apply, this.persist);

  final AppPreferences Function(AppPreferences) apply;
  final Future<void> Function() persist;
}
