import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/features/settings/providers/app_preferences_provider.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';

void main() {
  group('AppThemePreference theme mode mapping', () {
    test('maps every saved preference exhaustively', () {
      expect(AppThemePreference.system.themeMode, ThemeMode.system);
      expect(AppThemePreference.light.themeMode, ThemeMode.light);
      expect(AppThemePreference.dark.themeMode, ThemeMode.dark);
    });
  });

  group('PharmaGuideApp theme preference', () {
    testWidgets('uses the selected theme and updates immediately', (
      tester,
    ) async {
      final controller = _controller(initialTheme: AppThemePreference.light);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_appWith(controller));
      expect(_materialApp(tester).themeMode, ThemeMode.light);

      await controller.updateTheme(AppThemePreference.dark);
      await tester.pump();

      expect(_materialApp(tester).themeMode, ThemeMode.dark);
    });

    testWidgets('system mode follows simulated platform brightness', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final controller = _controller();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_appWith(controller));
      expect(_materialApp(tester).themeMode, ThemeMode.system);
      expect(_renderedTheme(tester).brightness, Brightness.light);
      expect(
        _renderedTheme(tester).extension<V2Palette>(),
        same(V2Palette.light),
      );

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(_renderedTheme(tester).brightness, Brightness.dark);
      expect(
        _renderedTheme(tester).extension<V2Palette>(),
        same(V2Palette.dark),
      );
    });
  });

  test(
    'persisted selection restores into a reconstructed controller',
    () async {
      final store = _MemoryStore();
      final first = AppPreferencesController(
        repository: AppPreferencesRepository(store),
      );
      await first.updateTheme(AppThemePreference.dark);
      first.dispose();

      final repository = AppPreferencesRepository(store);
      final restored = AppPreferencesController(
        repository: repository,
        initialPreferences: await repository.load(),
      );
      addTearDown(restored.dispose);

      expect(restored.preferences.theme, AppThemePreference.dark);
      expect(restored.preferences.theme.themeMode, ThemeMode.dark);
    },
  );

  test('bootstrap and routed app share one production preference brain', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final appSource = File('lib/app.dart').readAsStringSync();

    expect(
      RegExp(r'AppPreferencesController\(').allMatches(mainSource),
      hasLength(1),
      reason: '_runApp must construct one production controller',
    );
    expect(
      mainSource,
      contains('appPreferencesController: appPreferencesController'),
    );
    expect(
      mainSource,
      contains(
        'appPreferencesControllerProvider.overrideWith(\n'
        '          (_) => widget.appPreferencesController,\n'
        '          disposeNotifier: false,',
      ),
      reason: 'the ProviderScope must expose the bootstrap-owned controller',
    );
    expect(
      mainSource,
      contains('widget.appPreferencesController.preferences.theme.themeMode'),
      reason: 'the bootstrap MaterialApp must use the preloaded controller',
    );
    expect(
      RegExp(
        r'ref\.watch\(\s*appPreferencesControllerProvider,?\s*\)',
      ).hasMatch(appSource),
      isTrue,
      reason: 'the routed MaterialApp must watch the injected controller',
    );
    expect(mainSource, isNot(contains('themeMode: ThemeMode.system')));
    expect(appSource, isNot(contains('themeMode: ThemeMode.system')));
  });
}

Widget _appWith(AppPreferencesController controller) {
  return ProviderScope(
    overrides: [
      appPreferencesControllerProvider.overrideWith(
        (_) => controller,
        disposeNotifier: false,
      ),
    ],
    child: const PharmaGuideApp(),
  );
}

MaterialApp _materialApp(WidgetTester tester) {
  return tester.widget<MaterialApp>(find.byType(MaterialApp));
}

ThemeData _renderedTheme(WidgetTester tester) {
  final scaffold = tester.element(find.byType(Scaffold).first);
  return Theme.of(scaffold);
}

AppPreferencesController _controller({
  AppThemePreference initialTheme = AppThemePreference.system,
}) {
  return AppPreferencesController(
    repository: AppPreferencesRepository(_MemoryStore()),
    initialPreferences: AppPreferences(theme: initialTheme),
  );
}

class _MemoryStore implements AppPreferencesStore {
  final Map<String, Object> values = <String, Object>{};

  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<void> setBool(String key, bool value) async {
    values[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}
