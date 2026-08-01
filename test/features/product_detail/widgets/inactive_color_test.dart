// Tests for `inactiveColorRank` — pipeline-driven severity → inactive
// tone mapping. The function is consumed by `inactiveFromMap` in v2
// (`features/product_detail/v2/sections/ingredients_helpers.dart`),
// so its contract still ships in production. Ported from the legacy
// `ingredients_card_test.dart` 2026-05-17 (Phase 11.11 hygiene).

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';

void main() {
  group('inactiveColorRank — pipeline-driven severity', () {
    test('"high" → red', () {
      expect(inactiveColorRank({'harmful_severity': 'high'}), InactiveTone.red);
    });

    test('"moderate" → orange', () {
      expect(
        inactiveColorRank({'harmful_severity': 'moderate'}),
        InactiveTone.orange,
      );
    });

    test('"low" → yellow', () {
      expect(
        inactiveColorRank({'harmful_severity': 'low'}),
        InactiveTone.yellow,
      );
    });

    test('"none" → green', () {
      expect(
        inactiveColorRank({'harmful_severity': 'none'}),
        InactiveTone.green,
      );
    });

    test('missing severity_level key → green', () {
      expect(inactiveColorRank({'name': 'X'}), InactiveTone.green);
    });

    test('case-insensitive match', () {
      expect(inactiveColorRank({'harmful_severity': 'HIGH'}), InactiveTone.red);
      expect(
        inactiveColorRank({'harmful_severity': '  Moderate  '}),
        InactiveTone.orange,
      );
    });

    test('non-string severity → green (defensive)', () {
      expect(inactiveColorRank({'harmful_severity': 5}), InactiveTone.green);
    });

    test('tone colors use v2 severity palette', () {
      expect(InactiveTone.green.color(V2Palette.light), V2Palette.light.safe);
      expect(InactiveTone.yellow.color(V2Palette.light), V2Palette.light.caution);
      expect(InactiveTone.orange.color(V2Palette.light), V2Palette.light.avoid);
      expect(InactiveTone.red.color(V2Palette.light), V2Palette.light.contraindicated);
    });
  });

  group('inactiveColorRank — display_tone (v1.6.x penalty-aware)', () {
    test('"green" → green', () {
      expect(inactiveColorRank({'display_tone': 'green'}), InactiveTone.green);
    });

    test('"light_orange" → yellow (amber)', () {
      expect(
        inactiveColorRank({'display_tone': 'light_orange'}),
        InactiveTone.yellow,
      );
    });

    test('"dark_orange" → orange', () {
      expect(
        inactiveColorRank({'display_tone': 'dark_orange'}),
        InactiveTone.orange,
      );
    });

    test('"red" → red', () {
      expect(inactiveColorRank({'display_tone': 'red'}), InactiveTone.red);
    });

    test(
      'display_tone overrides severity_status (0-penalty capsule → green)',
      () {
        // The veg-capsule case: severity_status=suppress would read amber, but
        // B1 applied 0 penalty → display_tone=green must win.
        expect(
          inactiveColorRank({
            'display_tone': 'green',
            'severity_status': 'suppress',
          }),
          InactiveTone.green,
        );
      },
    );

    test('case-insensitive / whitespace', () {
      expect(inactiveColorRank({'display_tone': '  RED '}), InactiveTone.red);
    });

    test('absent display_tone falls back to severity_status', () {
      expect(
        inactiveColorRank({'severity_status': 'critical'}),
        InactiveTone.red,
      );
      expect(
        inactiveColorRank({'severity_status': 'suppress'}),
        InactiveTone.yellow,
      );
      expect(inactiveColorRank({'severity_status': 'n/a'}), InactiveTone.green);
    });

    test('non-string display_tone falls through (defensive)', () {
      expect(
        inactiveColorRank({'display_tone': 7, 'harmful_severity': 'high'}),
        InactiveTone.red,
      );
    });
  });
}
