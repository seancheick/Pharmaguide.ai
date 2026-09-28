import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_score_breakdown_card.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';

void main() {
  // Pillar bars measure product quality. They were painted with the safety
  // tokens (`safe` at >=50%, `monitor` below), so a "Dose 20/20" bar in
  // safety-green read as "this dose is safe". Quality bars use the brand
  // accent; the pillar label ("Strong", "Limited") and number carry strength.
  for (final palette in [V2Palette.light, V2Palette.dark]) {
    test('pillar bars never borrow a severity colour '
        '(${palette == V2Palette.light ? 'light' : 'dark'})', () {
      for (final score in [0.0, 5.0, 10.0, 14.0, 20.0]) {
        final tone = PGScoreBreakdownCard.pillarTone(score, 20, palette);
        expect(tone, palette.accent, reason: 'score $score/20');
        for (final severity in [
          palette.safe,
          palette.monitor,
          palette.caution,
          palette.avoid,
          palette.contraindicated,
        ]) {
          expect(tone, isNot(severity));
        }
      }
      expect(
        PGScoreBreakdownCard.pillarTone(null, 20, palette),
        palette.fgSubtle,
      );
    });
  }
}
