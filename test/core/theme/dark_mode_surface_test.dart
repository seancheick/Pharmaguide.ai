// Verifies screens actually follow the device appearance.
//
// The settings screen promises "PharmaGuide follows your device appearance."
// Before this work it did not: every Scaffold hardcoded the light background,
// so pages stayed light while modals — which correctly read the theme — went
// dark. That split is what the app looked like, and nothing tested it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';

Future<Color?> _scaffoldBackground(
  WidgetTester tester,
  ThemeData theme,
) async {
  await tester.pumpWidget(
    MaterialApp(
      // Keyed by brightness: pumping twice in one test would otherwise reuse
      // the first tree and read a stale colour.
      key: ValueKey(theme.brightness),
      theme: theme,
      // No backgroundColor: exactly how the screens are now written.
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
  final material = tester.widget<Material>(
    find
        .descendant(
          of: find.byType(Scaffold),
          matching: find.byType(Material),
        )
        .first,
  );
  return material.color;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('screens follow device appearance', () {
    testWidgets('a Scaffold with no override takes the light background', (
      tester,
    ) async {
      expect(
        await _scaffoldBackground(tester, V2Theme.light),
        V2Palette.light.bg,
      );
    });

    testWidgets('a Scaffold with no override takes the dark background', (
      tester,
    ) async {
      // The whole point: this was V2Colors.bg (near-white) in dark mode.
      expect(
        await _scaffoldBackground(tester, V2Theme.dark),
        V2Palette.dark.bg,
      );
    });

    testWidgets('light and dark backgrounds actually differ', (tester) async {
      final light = await _scaffoldBackground(tester, V2Theme.light);
      final dark = await _scaffoldBackground(tester, V2Theme.dark);
      expect(light, isNot(dark));
    });
  });

  group('system chrome follows brightness', () {
    Future<SystemUiOverlayStyle> overlayUnder(
      WidgetTester tester,
      ThemeData theme,
    ) async {
      late SystemUiOverlayStyle style;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(theme.brightness),
          theme: theme,
          home: Builder(
            builder: (context) {
              style = v2SystemOverlay(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return style;
    }

    testWidgets('light mode uses dark icons on a light bar', (tester) async {
      final style = await overlayUnder(tester, V2Theme.light);
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.systemNavigationBarColor, V2Palette.light.bg);
    });

    testWidgets('dark mode uses light icons on a dark bar', (tester) async {
      // Hardcoded Brightness.dark icons on a dark bar make the clock and
      // battery disappear — the same invisible-on-invisible failure as the
      // body text, but in OS chrome where it is easy to miss.
      final style = await overlayUnder(tester, V2Theme.dark);
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.systemNavigationBarColor, V2Palette.dark.bg);
    });

    testWidgets('icon brightness always inverts its surface', (tester) async {
      final light = await overlayUnder(tester, V2Theme.light);
      final dark = await overlayUnder(tester, V2Theme.dark);
      expect(
        light.statusBarIconBrightness,
        isNot(dark.statusBarIconBrightness),
        reason: 'chrome that does not invert is chrome that disappears',
      );
    });
  });

  group('no screen re-hardcodes its background', () {
    test('no Scaffold or AppBar pins V2Colors.bg', () {
      // Guards the fix: both default to brightness-resolved theme values, so
      // an explicit override is always a regression.
      final offenders = <String>[];
      final dir = Directory.current;
      for (final entity in dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (!entity.path.contains('/lib/')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].trim() != 'backgroundColor: V2Colors.bg,') continue;
          final prev = lines
              .sublist(0, i)
              .reversed
              .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
          if (prev.trimRight().endsWith('Scaffold(') ||
              prev.trimRight().endsWith('AppBar(')) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'These pin the light background and will not follow dark mode:\n'
            '${offenders.join('\n')}',
      );
    });
  });
}
