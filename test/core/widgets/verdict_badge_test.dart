import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';

void main() {
  group('VerdictBadge verdict contract', () {
    test('live catalog verdicts map to expected colors', () {
      expect(VerdictBadge.colorFor('SAFE'), V2Colors.safe);
      expect(VerdictBadge.colorFor('CAUTION'), V2Colors.caution);
      expect(VerdictBadge.colorFor('POOR'), V2Colors.avoid);
      expect(VerdictBadge.colorFor('BLOCKED'), V2Colors.contraindicated);
      expect(VerdictBadge.colorFor('NOT_SCORED'), V2Colors.fgSubtle);
      expect(VerdictBadge.colorFor('NUTRITION_ONLY'), V2Colors.fgSubtle);
    });

    test('live catalog verdicts map to user-facing labels', () {
      expect(VerdictBadge.labelFor('SAFE'), 'Safe');
      expect(VerdictBadge.labelFor('CAUTION'), 'Caution');
      expect(VerdictBadge.labelFor('POOR'), 'Poor');
      expect(VerdictBadge.labelFor('BLOCKED'), 'Blocked');
      expect(VerdictBadge.labelFor('NOT_SCORED'), 'Not scored');
      expect(VerdictBadge.labelFor('NUTRITION_ONLY'), 'Nutrition only');
    });

    test('retired aliases remain supported for cached rows and fixtures', () {
      expect(VerdictBadge.colorFor('RECOMMENDED'), V2Colors.safe);
      expect(VerdictBadge.colorFor('GOOD'), V2Colors.safe);
      expect(VerdictBadge.colorFor('REVIEW'), V2Colors.caution);
      expect(VerdictBadge.colorFor('MODERATE'), V2Colors.avoid);
      expect(VerdictBadge.colorFor('UNSAFE'), V2Colors.contraindicated);
    });

    test('unknown verdicts stay visually neutral', () {
      expect(VerdictBadge.colorFor('FUTURE_LABEL'), V2Colors.fgSubtle);
      expect(VerdictBadge.labelFor('FUTURE_LABEL'), 'FUTURE_LABEL');
    });

    test('normalizes whitespace and case', () {
      expect(VerdictBadge.colorFor('  caution  '), V2Colors.caution);
      expect(VerdictBadge.labelFor('  nutrition_only  '), 'Nutrition only');
    });
  });
}
