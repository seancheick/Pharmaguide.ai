// Tests for `inactiveColorRank` — pipeline-driven severity → inactive
// tone mapping. The function is consumed by `inactiveFromMap` in v2
// (`features/product_detail/v2/sections/ingredients_helpers.dart`),
// so its contract still ships in production. Ported from the legacy
// `ingredients_card_test.dart` 2026-05-17 (Phase 11.11 hygiene).

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
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
      expect(InactiveTone.green.color, V2Colors.safe);
      expect(InactiveTone.yellow.color, V2Colors.caution);
      expect(InactiveTone.orange.color, V2Colors.avoid);
      expect(InactiveTone.red.color, V2Colors.contraindicated);
    });
  });
}
