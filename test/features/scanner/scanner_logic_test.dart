// Tests for the scanner screen's pure verdict→color policy.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/features/scanner/scanner_logic.dart';

void main() {
  group('verdictFlashColor', () {
    test('RECOMMENDED → scoreExceptional', () {
      expect(verdictFlashColor('RECOMMENDED'), AppTheme.scoreExceptional);
    });

    test('GOOD → scoreExcellent', () {
      expect(verdictFlashColor('GOOD'), AppTheme.scoreExcellent);
    });

    test('REVIEW → severityCaution', () {
      expect(verdictFlashColor('REVIEW'), AppTheme.severityCaution);
    });

    test('MODERATE → severityCaution', () {
      expect(verdictFlashColor('MODERATE'), AppTheme.severityCaution);
    });

    test('BLOCKED → severityContraindicated', () {
      expect(verdictFlashColor('BLOCKED'), AppTheme.severityContraindicated);
    });

    test('UNSAFE → severityContraindicated', () {
      expect(verdictFlashColor('UNSAFE'), AppTheme.severityContraindicated);
    });

    test('lowercase verdict normalizes to uppercase', () {
      expect(verdictFlashColor('recommended'), AppTheme.scoreExceptional);
      expect(verdictFlashColor('blocked'), AppTheme.severityContraindicated);
    });

    test('mixed-case verdict normalizes to uppercase', () {
      expect(verdictFlashColor('Review'), AppTheme.severityCaution);
    });

    test('null verdict falls through to green default', () {
      expect(verdictFlashColor(null), AppTheme.scoreExcellent);
    });

    test('empty string falls through to green default', () {
      expect(verdictFlashColor(''), AppTheme.scoreExcellent);
    });

    test('unknown verdict falls through to green default', () {
      expect(verdictFlashColor('FUTURE_LABEL'), AppTheme.scoreExcellent);
    });
  });
}
