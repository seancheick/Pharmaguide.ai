// The score line renders clinically-meaningful colour, so it has to follow
// the device appearance.
//
// It did not. `ScoreTier.color` / `.textColor` were plain getters holding a
// single set of values authored "readable on cream"; dark mode rendered them
// verbatim and every tier failed there — `poor` worst at 2.33:1, below even
// the 3:1 large-text floor.
//
// score_tier_test.dart locks the token VALUES. This locks the wiring: that
// the widget actually asks for the appearance it is rendered in. Both halves
// are needed — correct tokens reached through a hardcoded brightness would
// still be wrong on screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_score_line.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    ThemeData theme,
    int score, {
    String? confidence,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        key: ValueKey(theme.brightness),
        theme: theme,
        home: Scaffold(
          body: PGScoreLine(
            score: score,
            prominent: true,
            confidence: confidence,
          ),
        ),
      ),
    );
  }

  Color? scoreColor(WidgetTester tester, int score) =>
      tester.widget<Text>(find.text('$score/100')).style?.color;

  Color? labelColor(WidgetTester tester, ScoreTier tier) =>
      tester.widget<Text>(find.text(tier.label)).style?.color;

  Color dotColor(WidgetTester tester) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(PGScoreLine),
            matching: find.byType(Container),
          )
          .first,
    );
    return (container.decoration! as BoxDecoration).color!;
  }

  group('PGScoreLine follows the device appearance', () {
    for (final score in [95, 85, 75, 65, 55, 20]) {
      final tier = legacyTierForScore(score);

      testWidgets('${tier.name} resolves light tokens under V2Theme.light', (
        tester,
      ) async {
        await pump(tester, V2Theme.light, score);
        expect(scoreColor(tester, score), tier.textColor(Brightness.light));
        expect(labelColor(tester, tier), tier.textColor(Brightness.light));
        expect(dotColor(tester), tier.color(Brightness.light));
      });

      testWidgets('${tier.name} resolves dark tokens under V2Theme.dark', (
        tester,
      ) async {
        await pump(tester, V2Theme.dark, score);
        expect(scoreColor(tester, score), tier.textColor(Brightness.dark));
        expect(labelColor(tester, tier), tier.textColor(Brightness.dark));
        expect(dotColor(tester), tier.color(Brightness.dark));
      });
    }

    testWidgets('light and dark actually differ', (tester) async {
      // Guards the whole point: a widget that ignored brightness would pass
      // every assertion above if both ramps happened to be identical.
      await pump(tester, V2Theme.light, 20);
      final light = scoreColor(tester, 20);
      await pump(tester, V2Theme.dark, 20);
      final dark = scoreColor(tester, 20);
      expect(light, isNot(dark));
    });

    testWidgets('moderate confidence keeps the tier without extra copy', (
      tester,
    ) async {
      await pump(tester, V2Theme.light, 85, confidence: 'moderate');

      expect(find.text('85/100'), findsOneWidget);
      expect(find.text('Strong'), findsOneWidget);
      expect(find.textContaining('Score confidence:'), findsNothing);
    });

    testWidgets('limited confidence keeps a neutral number without tier copy', (
      tester,
    ) async {
      await pump(tester, V2Theme.light, 85, confidence: 'low');

      expect(find.text('85/100'), findsOneWidget);
      expect(find.text('Strong'), findsNothing);
      expect(find.text('Score confidence: Limited'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PGScoreLine),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
    });
  });
}
