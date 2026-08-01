// WCAG contrast gate for both V2Palette instances.
//
// This is the test that would have caught the original bug. Dark mode shipped
// with `fg` at 1.01:1 on the dark surface — invisible text, not merely low
// contrast — and every severity tier below the 3:1 large-text floor. Nothing
// failed, because nothing was measuring.
//
// Thresholds are WCAG 2.1 AA: 4.5:1 for body text, 3:1 for large text, icons,
// and other non-text UI.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';

const _bodyText = 4.5;
const _largeTextAndUi = 3.0;

double _channel(int component) {
  final c = component / 255.0;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4) as double;
}

/// WCAG relative luminance.
double _luminance(Color color) {
  final r = _channel((color.r * 255).round());
  final g = _channel((color.g * 255).round());
  final b = _channel((color.b * 255).round());
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Composites a semi-transparent colour over an opaque background.
///
/// Without this, a tinted fill is measured as if it were the bare surface —
/// which is exactly how the severity pills passed review while rendering at
/// 2.11:1. Alpha is not decoration; it changes the effective background.
Color composite(Color fg, Color bg) {
  final a = fg.a;
  int mix(double f, double b) => ((a * f + (1 - a) * b) * 255).round();
  return Color.fromARGB(255, mix(fg.r, bg.r), mix(fg.g, bg.g), mix(fg.b, bg.b));
}

String _hex(Color c) =>
    '#${((c.a * 255).round() << 24 | (c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Building V2Theme resolves Geist/Newsreader; without this the test tries a
  // network fetch and fails on the font, not on contrast.
  GoogleFonts.config.allowRuntimeFetching = false;
  for (final entry in {
    'light': V2Palette.light,
    'dark': V2Palette.dark,
  }.entries) {
    final mode = entry.key;
    final p = entry.value;

    group('$mode palette contrast', () {
      // Every surface a foreground can legitimately land on.
      final surfaces = <String, Color>{
        'bg': p.bg,
        'surface': p.surface,
        'surfaceHigh': p.surfaceHigh,
        'surfaceHighest': p.surfaceHighest,
      };

      void expectAtLeast(
        String fgName,
        Color fg,
        double threshold, {
        required String usage,
      }) {
        for (final s in surfaces.entries) {
          final ratio = contrastRatio(fg, s.value);
          expect(
            ratio,
            greaterThanOrEqualTo(threshold),
            reason:
                '$mode: $fgName ${_hex(fg)} on ${s.key} ${_hex(s.value)} is '
                '${ratio.toStringAsFixed(2)}:1, below the '
                '${threshold.toStringAsFixed(1)}:1 required for $usage.',
          );
        }
      }

      test('primary and muted text meet body contrast', () {
        expectAtLeast('fg', p.fg, _bodyText, usage: 'body text');
        expectAtLeast('fgMuted', p.fgMuted, _bodyText, usage: 'body text');
      });

      test('accent meets body contrast', () {
        expectAtLeast('accent', p.accent, _bodyText, usage: 'accent text');
        expectAtLeast(
          'accentStrong',
          p.accentStrong,
          _largeTextAndUi,
          usage: 'accent UI',
        );
      });

      test('every severity tier clears the non-text UI floor', () {
        // 3:1 is the universal floor: severity renders as pills, badges, and
        // icons. See the dark-only test below for the stricter bar.
        expectAtLeast(
          'contraindicated',
          p.contraindicated,
          _largeTextAndUi,
          usage: 'severity UI',
        );
        expectAtLeast('avoid', p.avoid, _largeTextAndUi, usage: 'severity UI');
        expectAtLeast(
          'caution',
          p.caution,
          _largeTextAndUi,
          usage: 'severity UI',
        );
        expectAtLeast(
          'monitor',
          p.monitor,
          _largeTextAndUi,
          usage: 'severity UI',
        );
        expectAtLeast('safe', p.safe, _largeTextAndUi, usage: 'severity UI');
      });

      test('severity tiers stay visually distinct from one another', () {
        // Five tiers that all pass contrast but read as the same colour would
        // defeat the ordering they encode.
        final tiers = {
          'contraindicated': p.contraindicated,
          'avoid': p.avoid,
          'caution': p.caution,
          'monitor': p.monitor,
          'safe': p.safe,
        };
        final names = tiers.keys.toList();
        for (var i = 0; i < names.length; i++) {
          for (var j = i + 1; j < names.length; j++) {
            final a = tiers[names[i]]!;
            final b = tiers[names[j]]!;
            expect(
              a.toARGB32(),
              isNot(b.toARGB32()),
              reason: '$mode: ${names[i]} and ${names[j]} are the same colour',
            );
          }
        }
      });

      test('solid-fill foregrounds meet body-text contrast', () {
        final pairs = <String, ({Color fill, Color foreground})>{
          'accent': (fill: p.accent, foreground: p.onAccent),
          'accentStrong': (fill: p.accentStrong, foreground: p.onAccentStrong),
          'contraindicated': (
            fill: p.contraindicated,
            foreground: p.onContraindicated,
          ),
          'avoid': (fill: p.avoid, foreground: p.onAvoid),
          'caution': (fill: p.caution, foreground: p.onCaution),
          'monitor': (fill: p.monitor, foreground: p.onMonitor),
          'safe': (fill: p.safe, foreground: p.onSafe),
        };

        for (final pair in pairs.entries) {
          final ratio = contrastRatio(pair.value.foreground, pair.value.fill);
          expect(
            ratio,
            greaterThanOrEqualTo(_bodyText),
            reason:
                '$mode: ${pair.key} foreground ${_hex(pair.value.foreground)} '
                'on ${_hex(pair.value.fill)} is '
                '${ratio.toStringAsFixed(2)}:1.',
          );
        }
      });
    });
  }

  group('dark palette — the stricter bar', () {
    // The dark ramp was authored in this change, so it is held to full body
    // contrast on every dark surface rather than the 3:1 UI floor.
    final surfaces = <String, Color>{
      'bg': V2Palette.dark.bg,
      'surface': V2Palette.dark.surface,
      'surfaceHigh': V2Palette.dark.surfaceHigh,
      'surfaceHighest': V2Palette.dark.surfaceHighest,
    };

    test('every severity tier meets 4.5:1 on every dark surface', () {
      final tiers = {
        'contraindicated': V2Palette.dark.contraindicated,
        'avoid': V2Palette.dark.avoid,
        'caution': V2Palette.dark.caution,
        'monitor': V2Palette.dark.monitor,
        'safe': V2Palette.dark.safe,
      };
      for (final tier in tiers.entries) {
        for (final s in surfaces.entries) {
          final ratio = contrastRatio(tier.value, s.value);
          expect(
            ratio,
            greaterThanOrEqualTo(_bodyText),
            reason:
                'dark: ${tier.key} ${_hex(tier.value)} on ${s.key} '
                '${_hex(s.value)} is ${ratio.toStringAsFixed(2)}:1. The ramp '
                'must clear 4.5:1 on the LIGHTEST dark surface, not just the '
                'darkest — elevated cards are where severity actually renders.',
          );
        }
      }
    });

    test('subtle text meets the UI floor on every dark surface', () {
      for (final s in surfaces.entries) {
        expect(
          contrastRatio(V2Palette.dark.fgSubtle, s.value),
          greaterThanOrEqualTo(_largeTextAndUi),
          reason: 'dark: fgSubtle on ${s.key}',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Known pre-existing light-palette gaps, measured 2026-07-31.
  //
  // Recorded rather than asserted: these are authored brand values that predate
  // this change, and altering them is a palette redesign (out of scope). No
  // inverted "expect this to be bad" test, because that breaks the day someone
  // improves it — exactly backwards.
  //
  //   light fgSubtle #8A8D90  worst 2.85:1  — below the 3:1 UI floor
  //   light caution  #AD7A24  worst 3.21:1  — passes 3:1, below 4.5:1
  //   light monitor  #827140  worst 4.09:1  — passes 3:1, below 4.5:1
  //   light avoid    #B8542F  worst 4.13:1  — passes 3:1, below 4.5:1
  //
  // The universal 3:1 severity floor above covers all of these. Raising the
  // light ramp to 4.5:1 is a separate, deliberate palette decision.
  // ---------------------------------------------------------------------------

  group('severity pill — composited contrast', () {
    // The pill is the highest-stakes surface in the app: it is what a
    // pharmacist reads at a glance. These assert the REAL rendered pairing —
    // label colour against the fill composited over its surface — not the
    // label against a bare surface it never actually sits on.
    //
    // The label is 11.5-12.5pt bold. WCAG large text starts at 14pt bold, so
    // 4.5:1 applies and the 3:1 non-text floor is not available here.

    void expectPillReadable({
      required String mode,
      required String tier,
      required Color label,
      required Color fill,
      required Color surface,
    }) {
      final rendered = composite(fill, surface);
      final ratio = contrastRatio(label, rendered);
      expect(
        ratio,
        greaterThanOrEqualTo(_bodyText),
        reason:
            '$mode $tier: label ${_hex(label)} on fill composited to '
            '${_hex(rendered)} is ${ratio.toStringAsFixed(2)}:1.',
      );
    }

    test('dark pills use a neutral fill and stay readable', () {
      const p = V2Palette.dark;
      // Matches PGSeverityPill._style: dark fills with surfaceHigh, never a
      // tint of the label's own hue.
      for (final tier in {
        'contraindicated': p.contraindicated,
        'avoid': p.avoid,
        'caution': p.caution,
        'monitor': p.monitor,
        'safe': p.safe,
      }.entries) {
        expectPillReadable(
          mode: 'dark',
          tier: tier.key,
          label: tier.value,
          fill: p.surfaceHigh,
          surface: p.surface,
        );
      }
    });

    test('a same-hue dark tint would NOT be readable', () {
      // Guards the reason for the neutral fill. If someone reintroduces a
      // tinted dark pill, this documents why it fails.
      const p = V2Palette.dark;
      final tinted = composite(
        p.contraindicated.withValues(alpha: 0.22),
        p.surface,
      );
      expect(
        contrastRatio(p.contraindicated, tinted),
        lessThan(_bodyText),
        reason:
            'If this passes, a same-hue dark tint became viable — revisit the '
            'neutral-fill decision rather than leaving this as a guard.',
      );
    });
  });

  group('theme wiring', () {
    // Pumped rather than inspecting ThemeData directly: this exercises the
    // exact path widgets use, and building the theme bare trips GoogleFonts
    // font resolution in a unit test.
    Future<V2Palette> paletteUnder(WidgetTester tester, ThemeData theme) async {
      late V2Palette resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              resolved = context.v2;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return resolved;
    }

    testWidgets('context.v2 resolves the light palette', (tester) async {
      expect(await paletteUnder(tester, V2Theme.light), same(V2Palette.light));
    });

    testWidgets('context.v2 resolves the dark palette', (tester) async {
      expect(await paletteUnder(tester, V2Theme.dark), same(V2Palette.dark));
    });

    testWidgets('ColorScheme severity slots follow brightness', (tester) async {
      // These were pinned to light-mode values in both themes.
      late ColorScheme dark;
      await tester.pumpWidget(
        MaterialApp(
          theme: V2Theme.dark,
          home: Builder(
            builder: (context) {
              dark = Theme.of(context).colorScheme;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(dark.error, V2Palette.dark.contraindicated);
      expect(dark.tertiary, V2Palette.dark.safe);
    });

    test('the palette lerps rather than snapping', () {
      final mid = V2Palette.light.lerp(V2Palette.dark, 0.5);
      expect(mid.fg, isNot(V2Palette.light.fg));
      expect(mid.fg, isNot(V2Palette.dark.fg));
    });

    test('solid foregrounds stay readable throughout appearance changes', () {
      for (var step = 0; step <= 20; step++) {
        final t = step / 20;
        final p = V2Palette.light.lerp(V2Palette.dark, t);
        final pairs = <String, ({Color fill, Color foreground})>{
          'accent': (fill: p.accent, foreground: p.onAccent),
          'accentStrong': (fill: p.accentStrong, foreground: p.onAccentStrong),
          'contraindicated': (
            fill: p.contraindicated,
            foreground: p.onContraindicated,
          ),
          'avoid': (fill: p.avoid, foreground: p.onAvoid),
          'caution': (fill: p.caution, foreground: p.onCaution),
          'monitor': (fill: p.monitor, foreground: p.onMonitor),
          'safe': (fill: p.safe, foreground: p.onSafe),
        };
        for (final pair in pairs.entries) {
          expect(
            contrastRatio(pair.value.foreground, pair.value.fill),
            greaterThanOrEqualTo(_bodyText),
            reason: '${pair.key} loses contrast at theme interpolation t=$t',
          );
        }
      }
    });

    test('light and dark differ on every semantic token', () {
      // A token accidentally shared between palettes is the failure mode this
      // whole refactor exists to remove.
      expect(V2Palette.light.fg, isNot(V2Palette.dark.fg));
      expect(V2Palette.light.bg, isNot(V2Palette.dark.bg));
      expect(V2Palette.light.surface, isNot(V2Palette.dark.surface));
      expect(V2Palette.light.accent, isNot(V2Palette.dark.accent));
      expect(
        V2Palette.light.contraindicated,
        isNot(V2Palette.dark.contraindicated),
      );
      expect(V2Palette.light.safe, isNot(V2Palette.dark.safe));
    });
  });
}
