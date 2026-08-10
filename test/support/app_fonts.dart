// Deterministic real-glyph text for golden tests.
//
// flutter_test ships a placeholder font whose every glyph is a filled box, and
// GoogleFonts cannot close the gap on its own: `allowRuntimeFetching = false`
// blocks the network, and `assets/fonts/` is declared as a plain asset
// directory rather than a pubspec `fonts:` family, so nothing ever registers
// Geist with the engine.
//
// Whether a golden rendered real glyphs or boxes therefore depended on
// GoogleFonts warmth and TEST ORDER. The two med-nutrient masters were captured
// in different states — the first cold (boxes), the second warm (real glyphs) —
// and any failure in the first test aborted it before its first pump, which
// flipped the second to boxes and failed it too. That cascade cost a full
// diagnosis pass on 2026-08-09.
//
// Registering the bundled TTFs under the exact families GoogleFonts resolves
// to removes the coupling: goldens render identically on every machine, in any
// order, warm or cold.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Families the v2 type scale resolves to → the TTF that satisfies each.
///
/// Verified by probing V2Typography: `GoogleFonts.geist` at w400/w500 resolves
/// to `Geist_regular`/`Geist_500`, and `GoogleFonts.geistMono` at w500 to
/// `GeistMono_500`. The bare `Geist`/`GeistMono` entries cover the
/// `fontFamilyFallback` GoogleFonts attaches to every style, and the
/// `ThemeData(fontFamily: 'Geist')` the golden harness sets.
const _goldenFontFiles = <String, String>{
  'Geist_regular': 'assets/fonts/Geist-Regular.ttf',
  'Geist_500': 'assets/fonts/Geist-Medium.ttf',
  'Geist': 'assets/fonts/Geist-Regular.ttf',
  'GeistMono_500': 'assets/fonts/GeistMono-Medium.ttf',
  'GeistMono': 'assets/fonts/GeistMono-Medium.ttf',
};

/// Registers the bundled app fonts with the test engine.
///
/// Call from `setUpAll` in any test that compares rendered pixels. Cheap and
/// idempotent, but scoped deliberately: loading real fonts changes text
/// metrics, so tests that assert layout against the placeholder font are left
/// untouched.
///
/// NOTE: Newsreader (`V2Typography.display*`) is NOT bundled in `assets/fonts/`,
/// so display-scale text still falls back to the placeholder font. No current
/// golden renders it. A new golden that does must ship the Newsreader TTF and
/// add it here rather than quietly accept box glyphs.
///
/// Material icon glyphs are also still placeholder squares. Deliberately left
/// alone: MaterialIcons-Regular.otf lives in the Flutter SDK, not this repo, so
/// loading it would key the goldens to an SDK path and reintroduce exactly the
/// machine dependence this helper removes. Icons render as consistent squares
/// on every machine, which is stable — just not pretty. Ship the .otf in
/// `assets/fonts/` if a reviewer screenshot ever needs real icons.
Future<void> loadAppFonts() async {
  for (final entry in _goldenFontFiles.entries) {
    final file = File(entry.value);
    // Fail loudly. A renamed or dropped TTF must break the gate, never let
    // goldens silently revert to the box glyphs this helper exists to prevent.
    if (!file.existsSync()) {
      throw StateError(
        'golden font missing: ${entry.value} (family ${entry.key}). '
        'Restore it or update _goldenFontFiles — do not regenerate goldens '
        'without it, or they will re-pin placeholder box glyphs.',
      );
    }
    final bytes = await file.readAsBytes();
    await (FontLoader(entry.key)
          ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))))
        .load();
  }
}
