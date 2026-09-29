import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';

/// WCAG 2.x contrast ratio.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // Critique 2026-09-29: fgSubtle (#8A8D90) measured 3.17:1 on bg, below
  // AA, and it carries the product-detail disclaimer and data date. Every
  // text token must clear 4.5:1 on every surface it can sit on.
  const light = {
    'bg': V2Colors.bg,
    'surface': V2Colors.surface,
    'surfaceContainerLow': V2Colors.surfaceContainerLow,
    'surfaceContainerHighest': V2Colors.surfaceContainerHighest,
  };
  const dark = {
    'bgDark': V2Colors.bgDark,
    'surfaceDark': V2Colors.surfaceDark,
    'surfaceContainerLowDark': V2Colors.surfaceContainerLowDark,
    'surfaceContainerHighDark': V2Colors.surfaceContainerHighDark,
    'surfaceContainerHighestDark': V2Colors.surfaceContainerHighestDark,
  };
  const lightText = {
    'fg': V2Colors.fg,
    'fgMuted': V2Colors.fgMuted,
    'fgSubtle': V2Colors.fgSubtle,
  };
  const darkText = {
    'fgDark': V2Colors.fgDark,
    'fgMutedDark': V2Colors.fgMutedDark,
    'fgSubtleDark': V2Colors.fgSubtleDark,
  };

  for (final (texts, surfaces) in [(lightText, light), (darkText, dark)]) {
    for (final text in texts.entries) {
      for (final surface in surfaces.entries) {
        test('${text.key} on ${surface.key} meets AA 4.5:1', () {
          expect(
            _contrast(text.value, surface.value),
            greaterThanOrEqualTo(4.5),
          );
        });
      }
    }
  }

  test('subtle text stays lighter than muted text in both modes', () {
    expect(
      V2Colors.fgSubtle.computeLuminance(),
      greaterThan(V2Colors.fgMuted.computeLuminance()),
    );
    expect(
      V2Colors.fgSubtleDark.computeLuminance(),
      lessThan(V2Colors.fgMutedDark.computeLuminance()),
    );
  });
}
