// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T9.
//
// Boundary tests pin the inclusive-at-the-floor semantics so a `>` vs
// `>=` typo can't silently shift the entire tier system. Plus
// metadata invariants (every tier has a label, description, color;
// labels are unique; descriptions don't end with a period).

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';

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

    test('all 6 colors are distinct', () {
      // If two tiers share a color, the score dot becomes ambiguous —
      // a 90 and a 60 could read as the same severity to a colorblind
      // user with the dot alone. The label disambiguates, but we still
      // want each color to be unique so the visual signal is honest.
      final colors = ScoreTier.values.map((t) => t.color.toARGB32()).toSet();
      expect(colors, hasLength(ScoreTier.values.length));
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
      expect(
        ScoreTier.excellent.description,
        contains('Well-formulated'),
      );
      expect(
        ScoreTier.good.description,
        contains('Reliable option'),
      );
      expect(
        ScoreTier.fair.description,
        contains('Adequate formulation'),
      );
      expect(
        ScoreTier.lowQuality.description,
        contains('Notable concerns'),
      );
      expect(
        ScoreTier.poor.description,
        contains('Significant concerns'),
      );
    });

    test('color hue ordering — green tiers brighter than orange/red', () {
      // Defensive: Exceptional/Excellent/Good should all read as
      // "positive" (green-side) and the red value should be lower than
      // their green value. Conversely Poor/Low Quality should be
      // "concerning" (red-side, red >= green).
      for (final tier in [
        ScoreTier.exceptional,
        ScoreTier.excellent,
        ScoreTier.good,
      ]) {
        expect(
          (tier.color.g * 255.0).round() >
              (tier.color.r * 255.0).round(),
          isTrue,
          reason: '${tier.name} should be green-dominant',
        );
      }
      for (final tier in [ScoreTier.lowQuality, ScoreTier.poor]) {
        expect(
          (tier.color.r * 255.0).round() >
              (tier.color.g * 255.0).round(),
          isTrue,
          reason: '${tier.name} should be red-dominant',
        );
      }
    });
  });
}
