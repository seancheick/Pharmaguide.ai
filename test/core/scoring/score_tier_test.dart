// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T9.
//
// Boundary tests pin the inclusive-at-the-floor semantics so a `>` vs
// `>=` typo can't silently shift the entire tier system. Plus
// metadata invariants (every tier has a label, description, color;
// labels are unique; descriptions don't end with a period).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';

/// Every surface a tier token can land on. Checking only one is how the
/// dark ramp shipped unreadable.
List<Color> _surfacesOf(V2Palette p) => [
  p.bg,
  p.surface,
  p.surfaceLow,
  p.surfaceHigh,
  p.surfaceHighest,
];

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  group('tierForScore — boundary thresholds', () {
    test('90/100 boundary — 89 → Excellent, 90 → Exceptional', () {
      expect(tierForScore(89), ScoreTier.excellent);
      expect(tierForScore(90), ScoreTier.exceptional);
    });

    test('80/79 boundary — 79 → Good, 80 → Excellent', () {
      expect(tierForScore(79), ScoreTier.good);
      expect(tierForScore(80), ScoreTier.excellent);
    });

    test('70/69 boundary — 69 → Fair, 70 → Good', () {
      expect(tierForScore(69), ScoreTier.fair);
      expect(tierForScore(70), ScoreTier.good);
    });

    test('60/59 boundary — 59 → Low Quality, 60 → Fair', () {
      expect(tierForScore(59), ScoreTier.lowQuality);
      expect(tierForScore(60), ScoreTier.fair);
    });

    test('50/49 boundary — 49 → Poor, 50 → Low Quality', () {
      expect(tierForScore(49), ScoreTier.poor);
      expect(tierForScore(50), ScoreTier.lowQuality);
    });

    test('0/100 ends — 0 → Poor, 100 → Exceptional', () {
      expect(tierForScore(0), ScoreTier.poor);
      expect(tierForScore(100), ScoreTier.exceptional);
    });

    test('out-of-range clamps gracefully (over/under)', () {
      // Defensive: if a future score-overflow bug feeds in 105, we
      // shouldn't fall off the tier system — clamp to the highest
      // tier. Same for negative inputs → lowest tier.
      expect(tierForScore(105), ScoreTier.exceptional);
      expect(tierForScore(999), ScoreTier.exceptional);
      expect(tierForScore(-1), ScoreTier.poor);
      expect(tierForScore(-100), ScoreTier.poor);
    });

    test('mid-range sanity', () {
      // Quick sanity coverage at the middle of each band.
      expect(tierForScore(95), ScoreTier.exceptional);
      expect(tierForScore(85), ScoreTier.excellent);
      expect(tierForScore(75), ScoreTier.good);
      expect(tierForScore(65), ScoreTier.fair);
      expect(tierForScore(55), ScoreTier.lowQuality);
      expect(tierForScore(25), ScoreTier.poor);
    });
  });

  group('ScoreTierMeta — display + theme metadata', () {
    test('every tier has a non-empty label', () {
      for (final tier in ScoreTier.values) {
        expect(tier.label, isNotEmpty, reason: '${tier.name} label empty');
      }
    });

    test('every tier has a non-empty description', () {
      for (final tier in ScoreTier.values) {
        expect(
          tier.description,
          isNotEmpty,
          reason: '${tier.name} description empty',
        );
      }
    });

    test('description copy is sentence-case, no trailing period', () {
      // The hero renders the description as a sub-line, not a sentence.
      // Trailing periods would read as terminating something the user
      // hasn't read yet. Locked from the design contract.
      for (final tier in ScoreTier.values) {
        expect(
          tier.description.endsWith('.'),
          isFalse,
          reason: '${tier.name} description ends with a period',
        );
      }
    });

    test('all 6 labels are distinct', () {
      final labels = ScoreTier.values.map((t) => t.label).toSet();
      expect(labels, hasLength(ScoreTier.values.length));
    });

    test('all 6 descriptions are distinct', () {
      final descriptions = ScoreTier.values.map((t) => t.description).toSet();
      expect(descriptions, hasLength(ScoreTier.values.length));
    });

    test('all 6 colors are distinct in both appearances', () {
      // If two tiers share a color, the score dot becomes ambiguous —
      // a 90 and a 60 could read as the same severity to a colorblind
      // user with the dot alone. The label disambiguates, but we still
      // want each color to be unique so the visual signal is honest.
      for (final brightness in Brightness.values) {
        final colors = ScoreTier.values
            .map((t) => t.color(brightness).toARGB32())
            .toSet();
        expect(
          colors,
          hasLength(ScoreTier.values.length),
          reason: 'duplicate tier color in $brightness',
        );
      }
    });

    test('tier text colors meet 4.5:1 on EVERY surface, BOTH appearances', () {
      // The previous version of this test checked a single surface
      // (V2Palette.light.bg) in a single appearance. That is why the dark
      // ramp shipped broken: every tier failed on dark surfaces — `poor`
      // worst at 2.33:1, below even the 3:1 large-text floor — and nothing
      // here could see it. Checking one surface proves one surface.
      for (final (brightness, palette) in [
        (Brightness.light, V2Palette.light),
        (Brightness.dark, V2Palette.dark),
      ]) {
        for (final surface in _surfacesOf(palette)) {
          for (final tier in ScoreTier.values) {
            final contrast = _contrast(tier.textColor(brightness), surface);
            expect(
              contrast,
              greaterThanOrEqualTo(4.5),
              reason:
                  '${tier.name} text on ${_hex(surface)} in $brightness '
                  'is ${contrast.toStringAsFixed(2)}:1',
            );
          }
        }
      }
    });

    test('tier dot colors meet the 3:1 non-text floor everywhere', () {
      // `color` is the dot / pillar-bar / tint token, never body text, so
      // 3:1 applies rather than 4.5:1. It still has to be visible: the dot
      // is what a user scans first on the hero card.
      for (final (brightness, palette) in [
        (Brightness.light, V2Palette.light),
        (Brightness.dark, V2Palette.dark),
      ]) {
        for (final surface in _surfacesOf(palette)) {
          for (final tier in ScoreTier.values) {
            final contrast = _contrast(tier.color(brightness), surface);
            expect(
              contrast,
              greaterThanOrEqualTo(3.0),
              reason:
                  '${tier.name} dot on ${_hex(surface)} in $brightness '
                  'is ${contrast.toStringAsFixed(2)}:1',
            );
          }
        }
      }
    });

    test('locked label copy matches spec', () {
      // Pin the user-visible labels — any future "let's rename
      // Excellent to Premium" needs to update this test deliberately.
      expect(ScoreTier.exceptional.label, 'Exceptional');
      expect(ScoreTier.excellent.label, 'Excellent');
      expect(ScoreTier.good.label, 'Good');
      expect(ScoreTier.fair.label, 'Fair');
      expect(ScoreTier.lowQuality.label, 'Low Quality');
      expect(ScoreTier.poor.label, 'Poor');
    });

    test('locked description copy matches spec (key phrases)', () {
      // Don't pin the entire string (verbose), just the unique phrase
      // each tier promises. If the wording shifts, this test forces
      // a deliberate change rather than a silent one.
      expect(
        ScoreTier.exceptional.description,
        contains('High-quality ingredients'),
      );
      expect(ScoreTier.excellent.description, contains('Well-formulated'));
      expect(ScoreTier.good.description, contains('Reliable option'));
      expect(ScoreTier.fair.description, contains('Adequate formulation'));
      expect(ScoreTier.lowQuality.description, contains('Notable concerns'));
      expect(ScoreTier.poor.description, contains('Significant concerns'));
    });

    test('color hue ordering holds in both appearances', () {
      // Defensive: Exceptional/Excellent/Good should all read as
      // "positive" (green-side) and the red value should be lower than
      // their green value. Conversely Poor/Low Quality should be
      // "concerning" (red-side, red >= green). Both ramps are derived by
      // moving lightness only, so this must survive the derivation.
      for (final brightness in Brightness.values) {
        for (final tier in [
          ScoreTier.exceptional,
          ScoreTier.excellent,
          ScoreTier.good,
        ]) {
          final c = tier.color(brightness);
          expect(
            (c.g * 255.0).round() > (c.r * 255.0).round(),
            isTrue,
            reason: '${tier.name} should be green-dominant in $brightness',
          );
        }
        for (final tier in [ScoreTier.lowQuality, ScoreTier.poor]) {
          final c = tier.color(brightness);
          expect(
            (c.r * 255.0).round() > (c.g * 255.0).round(),
            isTrue,
            reason: '${tier.name} should be red-dominant in $brightness',
          );
        }
      }
    });
  });
}
