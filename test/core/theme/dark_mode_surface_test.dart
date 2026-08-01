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

Future<Color?> _scaffoldBackground(WidgetTester tester, ThemeData theme) async {
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
        .descendant(of: find.byType(Scaffold), matching: find.byType(Material))
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
      // The whole point: this was V2Palette.light.bg (near-white) in dark mode.
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
    test('no Scaffold or AppBar pins V2Palette.light.bg', () {
      // Guards the fix: both default to brightness-resolved theme values, so
      // an explicit override is always a regression.
      final offenders = <String>[];
      final dir = Directory.current;
      for (final entity
          in dir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        if (!entity.path.contains('/lib/')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].trim() != 'backgroundColor: V2Palette.light.bg,') {
            continue;
          }
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

  group('widgets use the semantic palette', () {
    test('only the theme layer reads raw V2Colors tokens', () {
      const rawTokenOwners = <String>{
        'lib/core/theme/v2/v2_palette.dart',
        'lib/core/theme/v2/v2_theme.dart',
      };
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relative = entity.path.replaceFirst(
          '${Directory.current.path}/',
          '',
        );
        if (rawTokenOwners.contains(relative)) continue;

        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('V2Colors.')) {
            offenders.add('$relative:${i + 1}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Widgets must resolve brightness through context.v2. Raw tokens '
            'hardcode one appearance:\n${offenders.join('\n')}',
      );
    });

    test('adaptive solid-fill widgets never hardcode a white foreground', () {
      // Computed, not enumerated. An allowlist only re-checks the files that
      // were already fixed; this checks the invariant on every file.
      //
      // pg_type_badge escaped the first sweep because it resolves colour
      // through `type.color(context.v2)` — the palette is never named at the
      // use site, so searching for `context.v2.accent` could not see it.
      // Matching on "touches the palette at all" catches that indirection.
      const themeOwners = <String>{
        // These author the on* values. `isDark ? bgDark : white` IS the
        // brightness resolution, not a bypass of it.
        'lib/core/theme/v2/v2_palette.dart',
        'lib/core/theme/v2/v2_theme.dart',
      };
      const fixedDarkChrome = <String>{
        // Always-dark chrome over the camera feed. Both palettes resolve
        // cameraOverlay* to the same constants, so white is correct here.
        'lib/features/scanner/scanner_screen.dart',
        'lib/features/scanner/v2/scanner_v2_screen.dart',
      };
      // White that resolves brightness on its own line is not a hardcode.
      final brightnessAware = RegExp(
        r'(Colors\.white[^;]*isDark)|(isDark[^;]*Colors\.white)',
      );
      final touchesPalette = RegExp(r'context\.v2\b|V2Palette');

      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relative = entity.path.replaceFirst(
          '${Directory.current.path}/',
          '',
        );
        if (themeOwners.contains(relative)) continue;
        if (fixedDarkChrome.contains(relative)) continue;

        final source = entity.readAsStringSync();
        if (!source.contains('Colors.white')) continue;
        if (!touchesPalette.hasMatch(source)) continue;

        final lines = source.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('Colors.white')) continue;
          if (brightnessAware.hasMatch(lines[i])) continue;
          offenders.add('$relative:${i + 1}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Brightness-aware fills require their matching context.v2.on* '
            'foreground; white fails against every dark-mode accent and '
            'severity fill — 1.64:1 at worst:\n${offenders.join('\n')}',
      );
    });
  });

  group('pinned headers repaint when the appearance changes', () {
    // A SliverPersistentHeader repaints ONLY when its delegate's
    // shouldRebuild says to. A theme value read inside the delegate's build
    // is therefore invisible to that check, and the header freezes on the
    // previous appearance — while the status-bar icons, which DO follow the
    // switch, go invisible against the stale bar. Caught on device; no
    // contrast maths can see it, because every colour involved is correct.
    // Only the repaint was missing.
    //
    // Comparing `Brightness` is not a fix. Brightness flips discretely at
    // the START of the theme animation while the palette lerps across it,
    // so the header rebuilds once, captures a mid-transition colour, and
    // freezes there — verified on device. Resolve theme values at the call
    // site and compare those; they change every frame.
    test('a delegate never reads the theme inside build', () {
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        final declaration = source.indexOf(
          'extends SliverPersistentHeaderDelegate',
        );
        if (declaration == -1) continue;

        final relative = entity.path.replaceFirst(
          '${Directory.current.path}/',
          '',
        );
        // Scope to the delegate class: the enclosing widget resolves the
        // theme legitimately, and it lives in the same file.
        final body = source.substring(declaration);
        for (final read in ['context.v2', 'Theme.of(context)']) {
          if (body.contains(read)) {
            offenders.add('$relative (delegate build reads $read)');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A persistent header cannot see theme changes it reads itself. '
            'Resolve the value where the delegate is constructed and compare '
            'it in shouldRebuild:\n${offenders.join('\n')}',
      );
    });
  });

  group('modal routes resolve their surface at build time', () {
    // A route outlives the build that created it. `PGModal.bottomSheet`
    // passed `Theme.of(context).colorScheme.surface` as the sheet
    // background, which baked one appearance into the route: switching
    // light/dark with a sheet open rebuilt the CONTENT to the new
    // brightness while the background stayed on the old one, putting
    // light-mode text on a dark-mode surface. Found on device at 4f98ee1.
    //
    // Same family as the persistent-header bug above: a theme value
    // captured at construction instead of resolved in build.

    test('only pg_modal.dart creates modal routes', () {
      // The gate below only has to inspect one file as long as this holds.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relative = entity.path.replaceFirst(
          '${Directory.current.path}/',
          '',
        );
        if (relative == 'lib/core/widgets/pg_modal.dart') continue;
        final source = entity.readAsStringSync();
        for (final ctor in [
          'showModalBottomSheet(',
          'showDialog(',
          'showGeneralDialog(',
        ]) {
          if (source.contains(ctor)) offenders.add('$relative calls $ctor');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Route creation belongs in PGModal so appearance handling is '
            'fixed in one place:\n${offenders.join('\n')}',
      );
    });

    test('PGModal never bakes a theme colour into a route', () {
      final source = File('lib/core/widgets/pg_modal.dart').readAsStringSync();
      final offenders = <String>[];
      final lines = source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('Theme.of(context)')) {
          offenders.add('lib/core/widgets/pg_modal.dart:${i + 1}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Leave the colour null and let bottomSheetTheme/dialogTheme supply '
            'it — those resolve on every build, a captured value never '
            'does:\n${offenders.join('\n')}',
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
