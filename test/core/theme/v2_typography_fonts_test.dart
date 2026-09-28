import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Newsreader was not bundled, so the app fetched it from fonts.gstatic.com
  // at runtime: the user's IP went to Google, and a first launch offline drew
  // the fallback serif. Every family and weight the type scale resolves to
  // must load from the app bundle with runtime fetching off.
  test('every font the type scale uses loads from the bundle', () async {
    V2Typography.useBundledFontsOnly();
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);

    final failures = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.contains('unable to load font')) {
        failures.add(message);
      }
    };
    addTearDown(() => debugPrint = original);

    for (final style in <TextStyle>[
      V2Typography.display(),
      V2Typography.displaySm(),
      V2Typography.displayXs(),
      V2Typography.title(),
      V2Typography.titleSm(),
      V2Typography.bodyXl(),
      V2Typography.body(),
      V2Typography.bodyMedium(),
      V2Typography.bodySm(),
      V2Typography.label(),
      V2Typography.caption(),
      V2Typography.eyebrow(),
      V2Typography.overline(),
      V2Typography.monoData(),
    ]) {
      expect(style.fontFamily, isNotNull);
    }
    // The Material text theme is built from Geist at other roles' weights.
    expect(V2Theme.light.textTheme.bodyMedium?.fontFamily, isNotNull);
    expect(V2Theme.dark.textTheme.titleLarge?.fontFamily, isNotNull);

    await GoogleFonts.pendingFonts();

    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
