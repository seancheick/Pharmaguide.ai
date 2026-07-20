// FIX (P2) regression lock — a CAUTION verdict must surface at the hero
// top-line.
//
// Before: the hero derived its tier purely from the numeric score
// (`tierForScore`) and only read the pipeline `verdict` for BLOCKED /
// NOT_SCORED. A dose-driven CAUTION (safety signal DOSE_OVER_UL_CAUTION /
// DOSE_OVER_UL_CRITICAL) on a product with a high formulation score
// rendered a green "85/100 Excellent" hero with no caution cue.
//
// After: `heroShowsCautionCue` decides (pure) whether a caution pill
// rides alongside the tier score line. It fires only when the verdict is
// CAUTION *and* the hero is actually showing a tier line — the BLOCKED
// banner, the NOT_SCORED hedge, and the low-coverage hedge each own their
// slot and must be left untouched.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_hero_section.dart';

void main() {
  group('heroShowsCautionCue — pure decision', () {
    test('CAUTION verdict + tier score line shows the cue', () {
      expect(
        heroShowsCautionCue(
          verdict: 'CAUTION',
          scoreDisplay: HeroScoreDisplay.tierScore,
        ),
        isTrue,
      );
    });

    test('CAUTION is case/whitespace tolerant', () {
      expect(
        heroShowsCautionCue(
          verdict: '  caution ',
          scoreDisplay: HeroScoreDisplay.tierScore,
        ),
        isTrue,
      );
    });

    test('no cue when the hero is not showing a tier line', () {
      for (final d in const [
        HeroScoreDisplay.none, // BLOCKED — banner owns it
        HeroScoreDisplay.notScored, // hedge owns it
        HeroScoreDisplay.limitedData, // low-coverage hedge owns it
      ]) {
        expect(
          heroShowsCautionCue(verdict: 'CAUTION', scoreDisplay: d),
          isFalse,
          reason: 'CAUTION must not add a cue to $d',
        );
      }
    });

    test('non-CAUTION verdicts never show the cue', () {
      for (final v in const [null, '', 'SAFE', 'POOR', 'NOT_SCORED']) {
        expect(
          heroShowsCautionCue(
            verdict: v,
            scoreDisplay: HeroScoreDisplay.tierScore,
          ),
          isFalse,
          reason: 'verdict "$v" must not show a caution cue',
        );
      }
    });
  });

  group('PGHeroSection caution cue widget', () {
    Future<void> pump(WidgetTester tester, Widget hero) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: hero)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('CAUTION verdict paints the caution cue next to the score', (
      tester,
    ) async {
      await pump(
        tester,
        const PGHeroSection(
          imageWidget: SizedBox(),
          productName: 'Over-UL Product',
          brandName: 'Test Brand',
          score: 85,
          verdict: 'CAUTION',
        ),
      );
      // Tier line still renders...
      expect(find.text('85/100'), findsOneWidget);
      // ...but the caution cue is now visible next to it.
      expect(find.text('Use caution'), findsOneWidget);
    });

    testWidgets('non-CAUTION verdict shows no caution cue', (tester) async {
      await pump(
        tester,
        const PGHeroSection(
          imageWidget: SizedBox(),
          productName: 'Safe Product',
          brandName: 'Test Brand',
          score: 85,
          verdict: 'SAFE',
        ),
      );
      expect(find.text('85/100'), findsOneWidget);
      expect(find.text('Use caution'), findsNothing);
    });

    testWidgets('no verdict passed → no cue (backward compatible)', (
      tester,
    ) async {
      await pump(
        tester,
        const PGHeroSection(
          imageWidget: SizedBox(),
          productName: 'Legacy Product',
          brandName: 'Test Brand',
          score: 85,
        ),
      );
      expect(find.text('85/100'), findsOneWidget);
      expect(find.text('Use caution'), findsNothing);
    });

    testWidgets('BLOCKED wins — no caution cue even with a CAUTION verdict', (
      tester,
    ) async {
      await pump(
        tester,
        const PGHeroSection(
          imageWidget: SizedBox(),
          productName: 'Blocked Product',
          brandName: 'Test Brand',
          score: 85,
          isBlocked: true,
          verdict: 'CAUTION',
        ),
      );
      // Blocked suppresses the score slot entirely — no tier line, no cue.
      expect(find.text('85/100'), findsNothing);
      expect(find.text('Use caution'), findsNothing);
    });
  });
}
