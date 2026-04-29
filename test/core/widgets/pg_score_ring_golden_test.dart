import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_score_ring.dart';

/// Golden-image regression tests for [PGScoreRing] — one per score tier.
///
/// These tests are the visual guard rail for the score ring color bands.
/// When anyone touches [AppTheme.score*] tokens, the thresholds in
/// `_colorFor`, or the painter's gradient math, these goldens will
/// capture the change and fail CI until someone intentionally
/// regenerates them.
///
/// Regenerate goldens with:
///     flutter test --update-goldens test/core/widgets/pg_score_ring_golden_test.dart
void main() {
  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      // Disable animations so the ring renders at its final state
      // deterministically. Real animation is covered by widget tests.
      builder: (context, widgetChild) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: true, textScaler: TextScaler.noScaling),
        child: widgetChild!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 120, height: 120, child: Center(child: child)),
        ),
      ),
    );
  }

  group('PGScoreRing golden — light mode', () {
    testWidgets('exceptional tier (score 95)', (tester) async {
      await tester.pumpWidget(
        wrap(const PGScoreRing(score: 95, label: 'score', size: 96)),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(PGScoreRing),
        matchesGoldenFile('goldens/pg_score_ring_exceptional.png'),
      );
    });

    testWidgets('excellent tier (score 78)', (tester) async {
      await tester.pumpWidget(
        wrap(const PGScoreRing(score: 78, label: 'score', size: 96)),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(PGScoreRing),
        matchesGoldenFile('goldens/pg_score_ring_excellent.png'),
      );
    });

    testWidgets('good tier (score 62)', (tester) async {
      await tester.pumpWidget(
        wrap(const PGScoreRing(score: 62, label: 'score', size: 96)),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(PGScoreRing),
        matchesGoldenFile('goldens/pg_score_ring_good.png'),
      );
    });

    testWidgets('fair tier (score 48)', (tester) async {
      await tester.pumpWidget(
        wrap(const PGScoreRing(score: 48, label: 'score', size: 96)),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(PGScoreRing),
        matchesGoldenFile('goldens/pg_score_ring_fair.png'),
      );
    });

    testWidgets('below average tier (score 32)', (tester) async {
      await tester.pumpWidget(
        wrap(const PGScoreRing(score: 32, label: 'score', size: 96)),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(PGScoreRing),
        matchesGoldenFile('goldens/pg_score_ring_below_avg.png'),
      );
    });

    testWidgets('poor tier (score 18)', (tester) async {
      await tester.pumpWidget(
        wrap(const PGScoreRing(score: 18, label: 'score', size: 96)),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(PGScoreRing),
        matchesGoldenFile('goldens/pg_score_ring_poor.png'),
      );
    });

    testWidgets('insufficient data (score null)', (tester) async {
      await tester.pumpWidget(
        wrap(const PGScoreRing(score: null, label: 'no data', size: 96)),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(PGScoreRing),
        matchesGoldenFile('goldens/pg_score_ring_insufficient.png'),
      );
    });
  });

  group('PGScoreRing behavior', () {
    testWidgets('renders Semantics label with score and tier', (tester) async {
      // 87 is in the exceptional tier (≥85 per PGScoreRing._colorFor).
      await tester.pumpWidget(wrap(const PGScoreRing(score: 87, size: 96)));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('87 out of 100, exceptional score'),
        findsOneWidget,
      );
    });

    testWidgets('renders Semantics label for insufficient data', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const PGScoreRing(score: null, size: 96)));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(
          'Score unavailable. Not enough data to rate this product.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('respects disableAnimations (reduce motion)', (tester) async {
      // With disableAnimations: true, the ring should jump to final
      // progress immediately — we verify by checking that the score
      // number is already at its final value without pumping frames.
      await tester.pumpWidget(wrap(const PGScoreRing(score: 85, size: 96)));
      // Single pump, no settle — if animation was running, the score
      // would still be 0 here. disableAnimations forces the final value.
      await tester.pump();
      expect(find.text('85'), findsOneWidget);
    });
  });
}
