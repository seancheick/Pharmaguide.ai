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
  group('legacyTierForScore — pipeline-compatible fallback thresholds', () {
    test('95/94 boundary — 94 → Excellent, 95 → Elite', () {
      expect(legacyTierForScore(94), ScoreTier.excellent);
      expect(legacyTierForScore(95), ScoreTier.elite);
    });

    test('90/89 boundary — 89 → Strong, 90 → Excellent', () {
      expect(legacyTierForScore(89), ScoreTier.strong);
      expect(legacyTierForScore(90), ScoreTier.excellent);
    });

    test('80/79 boundary — 79 → Acceptable, 80 → Strong', () {
      expect(legacyTierForScore(79), ScoreTier.acceptable);
      expect(legacyTierForScore(80), ScoreTier.strong);
    });

    test('70/69 boundary — 69 → Weak, 70 → Acceptable', () {
      expect(legacyTierForScore(69), ScoreTier.weak);
      expect(legacyTierForScore(70), ScoreTier.acceptable);
    });

    test('55/54 boundary — 54 → Poor, 55 → Weak', () {
      expect(legacyTierForScore(54), ScoreTier.poor);
      expect(legacyTierForScore(55), ScoreTier.weak);
    });

    test('0/100 ends — 0 → Poor, 100 → Elite', () {
      expect(legacyTierForScore(0), ScoreTier.poor);
      expect(legacyTierForScore(100), ScoreTier.elite);
    });

    test('out-of-range clamps gracefully (over/under)', () {
      expect(legacyTierForScore(105), ScoreTier.elite);
      expect(legacyTierForScore(999), ScoreTier.elite);
      expect(legacyTierForScore(-1), ScoreTier.poor);
      expect(legacyTierForScore(-100), ScoreTier.poor);
    });

    test('mid-range sanity', () {
      expect(legacyTierForScore(97), ScoreTier.elite);
      expect(legacyTierForScore(92), ScoreTier.excellent);
      expect(legacyTierForScore(85), ScoreTier.strong);
      expect(legacyTierForScore(75), ScoreTier.acceptable);
      expect(legacyTierForScore(60), ScoreTier.weak);
      expect(legacyTierForScore(25), ScoreTier.poor);
    });
  });

  group('catalogTier — shipped tier is authoritative', () {
    test('catalog value wins when the rounded score suggests another band', () {
      expect(
        catalogTier(qualityTier: 'Acceptable', legacyScore: 80),
        ScoreTier.acceptable,
      );
    });

    test('all pipeline labels parse case-insensitively', () {
      expect(
        [
          'elite',
          'EXCELLENT',
          'Strong',
          'acceptable',
          'Weak',
          'poor',
        ].map((label) => catalogTier(qualityTier: label, legacyScore: 0)),
        ScoreTier.values,
      );
    });

    test('missing or unknown catalog values use the named legacy fallback', () {
      expect(catalogTier(qualityTier: null, legacyScore: 82), ScoreTier.strong);
      expect(
        catalogTier(qualityTier: 'future-tier', legacyScore: 82),
        ScoreTier.strong,
      );
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
      expect(ScoreTier.elite.label, 'Elite');
      expect(ScoreTier.excellent.label, 'Excellent');
      expect(ScoreTier.strong.label, 'Strong');
      expect(ScoreTier.acceptable.label, 'Acceptable');
      expect(ScoreTier.weak.label, 'Weak');
      expect(ScoreTier.poor.label, 'Poor');
    });

    test('locked description copy matches spec (key phrases)', () {
      // Don't pin the entire string (verbose), just the unique phrase
      // each tier promises. If the wording shifts, this test forces
      // a deliberate change rather than a silent one.
      expect(ScoreTier.elite.description, contains('High-quality ingredients'));
      expect(ScoreTier.excellent.description, contains('Well-formulated'));
      expect(ScoreTier.strong.description, contains('Reliable option'));
      expect(
        ScoreTier.acceptable.description,
        contains('Adequate formulation'),
      );
      expect(ScoreTier.weak.description, contains('Notable concerns'));
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
          ScoreTier.elite,
          ScoreTier.excellent,
          ScoreTier.strong,
        ]) {
          final c = tier.color(brightness);
          expect(
            (c.g * 255.0).round() > (c.r * 255.0).round(),
            isTrue,
            reason: '${tier.name} should be green-dominant in $brightness',
          );
        }
        for (final tier in [ScoreTier.weak, ScoreTier.poor]) {
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
