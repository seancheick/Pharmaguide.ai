// Tests for the scanner screen's pure verdict→color policy.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_verdict_reveal.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/features/scanner/scanner_logic.dart';

void main() {
  group('verdictRevealKind', () {
    test('safe-tier verdicts → success', () {
      expect(verdictRevealKind('SAFE'), PGVerdictKind.success);
      expect(verdictRevealKind('GOOD'), PGVerdictKind.success);
      expect(verdictRevealKind('RECOMMENDED'), PGVerdictKind.success);
    });

    test(
      'attention-tier, invalid contract values, and unknown → attention',
      () {
        expect(verdictRevealKind('CAUTION'), PGVerdictKind.attention);
        expect(verdictRevealKind('BLOCKED'), PGVerdictKind.attention);
        expect(verdictRevealKind('NOT_SCORED'), PGVerdictKind.attention);
        expect(verdictRevealKind('MONITOR'), PGVerdictKind.attention);
        expect(verdictRevealKind(null), PGVerdictKind.attention);
      },
    );
  });

  group('verdictFlashColor', () {
    test('SAFE → v2 safe', () {
      expect(verdictFlashColor('SAFE'), V2Colors.safe);
    });

    test('CAUTION → v2 caution', () {
      expect(verdictFlashColor('CAUTION'), V2Colors.caution);
    });

    test('POOR → v2 avoid', () {
      expect(verdictFlashColor('POOR'), V2Colors.avoid);
    });

    test('RECOMMENDED → v2 safe', () {
      expect(verdictFlashColor('RECOMMENDED'), V2Colors.safe);
    });

    test('GOOD → v2 safe', () {
      expect(verdictFlashColor('GOOD'), V2Colors.safe);
    });

    test('REVIEW → v2 caution', () {
      expect(verdictFlashColor('REVIEW'), V2Colors.caution);
    });

    test('MODERATE → v2 caution', () {
      expect(verdictFlashColor('MODERATE'), V2Colors.caution);
    });

    test('BLOCKED → v2 contraindicated', () {
      expect(verdictFlashColor('BLOCKED'), V2Colors.contraindicated);
    });

    test('UNSAFE → v2 contraindicated', () {
      expect(verdictFlashColor('UNSAFE'), V2Colors.contraindicated);
    });

    test('NOT_SCORED and NUTRITION_ONLY → v2 neutral', () {
      expect(verdictFlashColor('NOT_SCORED'), V2Colors.fgSubtle);
      expect(verdictFlashColor('NUTRITION_ONLY'), V2Colors.fgSubtle);
    });

    test('lowercase verdict normalizes to uppercase', () {
      expect(verdictFlashColor('recommended'), V2Colors.safe);
      expect(verdictFlashColor('blocked'), V2Colors.contraindicated);
    });

    test('mixed-case verdict normalizes to uppercase', () {
      expect(verdictFlashColor('Review'), V2Colors.caution);
    });

    test('null verdict falls through to neutral unknown', () {
      expect(verdictFlashColor(null), V2Colors.fgSubtle);
    });

    test('empty string falls through to neutral unknown', () {
      expect(verdictFlashColor(''), V2Colors.fgSubtle);
    });

    test('unknown verdict falls through to neutral unknown', () {
      expect(verdictFlashColor('FUTURE_LABEL'), V2Colors.fgSubtle);
    });
  });
}
