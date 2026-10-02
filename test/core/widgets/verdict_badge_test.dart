import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/data/verdict_vocab.dart';
import 'package:pharmaguide/core/data/vocab_registry.dart';
import 'package:pharmaguide/core/widgets/verdict_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('VerdictBadge safety display and cache compatibility', () {
    tearDown(() => VocabRegistry.instance.debugReset());

    test(
      'initialized vocab cannot give legacy quality labels a safety tone',
      () async {
        VocabRegistry.instance.debugSeed(verdicts: await loadVerdictVocab());
        for (final palette in [V2Palette.light, V2Palette.dark]) {
          for (final token in ['SAFE', 'POOR', 'GOOD', 'RECOMMENDED']) {
            expect(
              VerdictBadge.colorFor(palette, token),
              palette.fgSubtle,
              reason: token,
            );
          }
        }
        expect(VerdictBadge.labelFor('POOR'), 'Poor quality');
        expect(VerdictBadge.labelFor('SAFE'), 'Safe');
      },
    );
    test('live catalog verdicts map to expected colors', () {
      expect(
        VerdictBadge.colorFor(V2Palette.light, 'SAFE'),
        V2Palette.light.fgSubtle,
      );
      expect(
        VerdictBadge.colorFor(V2Palette.light, 'CAUTION'),
        V2Palette.light.caution,
      );
      // Legacy quality labels carry no safety tone; ScoreTier owns quality.
      expect(
        VerdictBadge.colorFor(V2Palette.light, 'POOR'),
        V2Palette.light.fgSubtle,
      );
      expect(
        VerdictBadge.colorFor(V2Palette.dark, 'POOR'),
        V2Palette.dark.fgSubtle,
      );
      expect(
        VerdictBadge.colorFor(V2Palette.light, 'POOR'),
        isNot(V2Palette.light.avoid),
      );
      expect(
        VerdictBadge.colorFor(V2Palette.light, 'BLOCKED'),
        V2Palette.light.contraindicated,
      );
      expect(
        VerdictBadge.colorFor(V2Palette.light, 'NOT_SCORED'),
        V2Palette.light.fgSubtle,
      );
      expect(
        VerdictBadge.colorFor(V2Palette.light, 'NUTRITION_ONLY'),
        V2Palette.light.fgSubtle,
      );
    });

    test('live catalog verdicts map to user-facing labels', () {
      expect(VerdictBadge.labelFor('SAFE'), 'Safe');
      expect(VerdictBadge.labelFor('CAUTION'), 'Caution');
      expect(VerdictBadge.labelFor('POOR'), 'Poor');
      expect(
        VerdictBadge.labelFor('NO_KNOWN_CATALOG_CONCERN'),
        'No catalog concern',
      );
      expect(VerdictBadge.labelFor('NOT_ASSESSED'), 'Not assessed');
      expect(VerdictBadge.labelFor('BLOCKED'), 'Blocked');
      expect(VerdictBadge.labelFor('NOT_SCORED'), 'Not scored');
      expect(VerdictBadge.labelFor('NUTRITION_ONLY'), 'Nutrition only');
    });

    test('retired quality aliases remain readable but never imply safety', () {
      expect(
        VerdictBadge.colorFor(V2Palette.light, 'RECOMMENDED'),
        V2Palette.light.fgSubtle,
      );
      expect(
        VerdictBadge.colorFor(V2Palette.light, 'GOOD'),
        V2Palette.light.fgSubtle,
      );
      expect(
        VerdictBadge.colorFor(V2Palette.light, 'REVIEW'),
        V2Palette.light.caution,
      );
      expect(
        VerdictBadge.colorFor(V2Palette.light, 'MODERATE'),
        V2Palette.light.avoid,
      );
      expect(
        VerdictBadge.colorFor(V2Palette.light, 'UNSAFE'),
        V2Palette.light.contraindicated,
      );
    });

    test(
      'unrecognized non-empty verdict fails toward caution, not neutral',
      () {
        // Contract drift — the pipeline emitted a verdict the app doesn't
        // know. Rendering it as a calm neutral/gray chip would let a
        // future/corrupted BLOCKED-class verdict slip past every blocked
        // gate, so colorFor fails toward CAUTION tone (not neutral, not safe).
        expect(
          VerdictBadge.colorFor(V2Palette.light, 'FUTURE_LABEL'),
          V2Palette.light.caution,
        );
        // labelFor still echoes the raw value so the corrupt verdict is
        // visible for debugging rather than masked behind a generic word.
        expect(VerdictBadge.labelFor('FUTURE_LABEL'), 'FUTURE_LABEL');
      },
    );

    test('empty / whitespace verdict stays neutral (no verdict yet)', () {
      expect(
        VerdictBadge.colorFor(V2Palette.light, ''),
        V2Palette.light.fgSubtle,
      );
      expect(
        VerdictBadge.colorFor(V2Palette.light, '   '),
        V2Palette.light.fgSubtle,
      );
    });

    test('normalizes whitespace and case', () {
      expect(
        VerdictBadge.colorFor(V2Palette.light, '  caution  '),
        V2Palette.light.caution,
      );
      expect(VerdictBadge.labelFor('  nutrition_only  '), 'Nutrition only');
    });
  });
}
