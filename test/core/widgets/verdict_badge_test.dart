import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';

void main() {
  group('VerdictBadge verdict contract', () {
    test('live catalog verdicts map to expected colors', () {
      expect(VerdictBadge.colorFor('SAFE'), AppTheme.scoreExcellent);
      expect(VerdictBadge.colorFor('CAUTION'), AppTheme.scoreFair);
      expect(VerdictBadge.colorFor('POOR'), AppTheme.scoreLow);
      expect(
        VerdictBadge.colorFor('BLOCKED'),
        AppTheme.severityContraindicated,
      );
      expect(VerdictBadge.colorFor('NOT_SCORED'), AppTheme.insufficientData);
      expect(
        VerdictBadge.colorFor('NUTRITION_ONLY'),
        AppTheme.insufficientData,
      );
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
      expect(VerdictBadge.colorFor('RECOMMENDED'), AppTheme.scoreExceptional);
      expect(VerdictBadge.colorFor('GOOD'), AppTheme.scoreExcellent);
      expect(VerdictBadge.colorFor('REVIEW'), AppTheme.scoreFair);
      expect(VerdictBadge.colorFor('MODERATE'), AppTheme.scoreLow);
      expect(VerdictBadge.colorFor('UNSAFE'), AppTheme.severityContraindicated);
    });

    test('unknown verdicts stay visually neutral', () {
      expect(VerdictBadge.colorFor('FUTURE_LABEL'), AppTheme.insufficientData);
      expect(VerdictBadge.labelFor('FUTURE_LABEL'), 'FUTURE_LABEL');
    });

    test('normalizes whitespace and case', () {
      expect(VerdictBadge.colorFor('  caution  '), AppTheme.scoreFair);
      expect(VerdictBadge.labelFor('  nutrition_only  '), 'Nutrition only');
    });
  });
}
