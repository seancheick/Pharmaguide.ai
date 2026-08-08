import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';

final appPreferencesControllerProvider =
    ChangeNotifierProvider<AppPreferencesController>((ref) {
      return AppPreferencesController(
        repository: AppPreferencesRepository(_DefaultAppPreferencesStore()),
      );
    });

extension AppThemePreferenceThemeMode on AppThemePreference {
  ThemeMode get themeMode => switch (this) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };
}

class _DefaultAppPreferencesStore implements AppPreferencesStore {
  @override
  Future<bool?> getBool(String key) async => null;

  @override
  Future<String?> getString(String key) async => null;

  @override
  Future<void> setBool(String key, bool value) async {}

  @override
  Future<void> setString(String key, String value) async {}
}
