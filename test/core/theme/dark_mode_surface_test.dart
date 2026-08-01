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

  group('the extension is registered where it matters', () {
    // This replaces a per-widget assert on context.v2. The fallback
    // (V2Palette.of(brightness)) is already correct, so the only invariant
    // worth enforcing is that the real app themes carry the extension —
    // one assertion instead of one per widget.
    test('both V2Theme entry points register V2Palette', () {
      expect(
        V2Theme.light.extension<V2Palette>(),
        same(V2Palette.light),
        reason: 'V2Theme.light must carry the palette',
      );
      expect(
        V2Theme.dark.extension<V2Palette>(),
        same(V2Palette.dark),
        reason: 'V2Theme.dark must carry the palette',
      );
    });

    test('both app entry points wire V2Theme with system brightness', () {
      // lib/app.dart and lib/main.dart each build a MaterialApp; if either
      // stops passing V2Theme, widgets silently drop to the fallback and the
      // registered extension stops mattering.
      for (final path in ['lib/app.dart', 'lib/main.dart']) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('V2Theme.light'),
          isTrue,
          reason: '$path must pass V2Theme.light',
        );
        expect(
          src.contains('V2Theme.dark'),
          isTrue,
          reason: '$path must pass V2Theme.dark as darkTheme',
        );
        expect(
          src.contains('ThemeMode.system'),
          isTrue,
          reason: '$path must follow the device appearance',
        );
      }
    });

    testWidgets('a widget without the extension still resolves by brightness', (
      tester,
    ) async {
      // The fallback path: correct, not a silent light default.
      late V2Palette resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              resolved = context.v2;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, same(V2Palette.dark));
    });
  });
}
