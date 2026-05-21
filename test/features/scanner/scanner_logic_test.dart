// Tests for the scanner screen's pure verdict→color policy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/features/scanner/scanner_logic.dart';

void main() {
  group('verdictFlashColor', () {
    test('SAFE → scoreExcellent', () {
      expect(verdictFlashColor('SAFE'), AppTheme.scoreExcellent);
    });

    test('CAUTION → severityCaution', () {
      expect(verdictFlashColor('CAUTION'), AppTheme.severityCaution);
    });

    test('POOR → scoreLow', () {
      expect(verdictFlashColor('POOR'), AppTheme.scoreLow);
    });

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

    test('NOT_SCORED and NUTRITION_ONLY → insufficientData', () {
      expect(verdictFlashColor('NOT_SCORED'), AppTheme.insufficientData);
      expect(verdictFlashColor('NUTRITION_ONLY'), AppTheme.insufficientData);
    });

    test('lowercase verdict normalizes to uppercase', () {
      expect(verdictFlashColor('recommended'), AppTheme.scoreExceptional);
      expect(verdictFlashColor('blocked'), AppTheme.severityContraindicated);
    });

    test('mixed-case verdict normalizes to uppercase', () {
      expect(verdictFlashColor('Review'), AppTheme.severityCaution);
    });

    test('null verdict falls through to neutral unknown', () {
      expect(verdictFlashColor(null), AppTheme.insufficientData);
    });

    test('empty string falls through to neutral unknown', () {
      expect(verdictFlashColor(''), AppTheme.insufficientData);
    });

    test('unknown verdict falls through to neutral unknown', () {
      expect(verdictFlashColor('FUTURE_LABEL'), AppTheme.insufficientData);
    });
  });

  group('verdictFlashIcon', () {
    test('positive verdicts use check icon', () {
      expect(verdictFlashIcon('RECOMMENDED'), Icons.check_circle_rounded);
      expect(verdictFlashIcon('SAFE'), Icons.check_circle_rounded);
      expect(verdictFlashIcon('GOOD'), Icons.check_circle_rounded);
    });

    test('caution and poor verdicts do not use success iconography', () {
      expect(verdictFlashIcon('CAUTION'), Icons.warning_rounded);
      expect(verdictFlashIcon('REVIEW'), Icons.warning_rounded);
      expect(verdictFlashIcon('MODERATE'), Icons.warning_rounded);
      expect(verdictFlashIcon('POOR'), Icons.warning_rounded);
    });

    test('blocked and unknown verdicts avoid check icon', () {
      expect(verdictFlashIcon('BLOCKED'), Icons.warning_rounded);
      expect(verdictFlashIcon('UNSAFE'), Icons.warning_rounded);
      expect(verdictFlashIcon('NOT_SCORED'), Icons.info_outline_rounded);
      expect(verdictFlashIcon('FUTURE_LABEL'), Icons.info_outline_rounded);
      expect(verdictFlashIcon(null), Icons.info_outline_rounded);
    });
  });
}
