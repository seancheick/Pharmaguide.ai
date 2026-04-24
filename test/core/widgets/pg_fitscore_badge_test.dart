import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_fitscore_badge.dart';

/// Widget tests for [PGFitScoreBadge] — one per personal-fit state.
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );
  }

  FitScoreResult buildResult({
    required FitAssessmentState state,
    List<String> missing = const [],
    List<String> reasons = const [],
  }) {
    return FitScoreResult(
      scoreFit20: 0,
      scoreCombined100: 75,
      e1: 0,
      e2a: 0,
      e2b: 0,
      e2c: 0,
      missingFields: missing,
      maxPossible: 100,
      state: state,
      reasons: reasons,
    );
  }

  group('PGFitScoreBadge — state rendering', () {
    testWidgets('null result renders nothing (SizedBox.shrink)',
        (tester) async {
      await tester.pumpWidget(wrap(
        const PGFitScoreBadge(result: null),
      ));
      // SizedBox.shrink has zero-size
      final box = tester.getSize(find.byType(PGFitScoreBadge));
      expect(box.width, 0);
      expect(box.height, 0);
    });

    testWidgets('strong match shows "Strong match"',
        (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(
          result: buildResult(state: FitAssessmentState.strongMatch),
        ),
      ));
      expect(find.text('Strong match'), findsOneWidget);
    });

    testWidgets('good fit shows "Good fit"', (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(
          result: buildResult(state: FitAssessmentState.goodFit),
        ),
      ));
      expect(find.text('Good fit'), findsOneWidget);
    });

    testWidgets('limited fit shows "Limited fit"',
        (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(
          result: buildResult(state: FitAssessmentState.limitedFit),
        ),
      ));
      expect(find.text('Limited fit'), findsOneWidget);
    });

    testWidgets('not recommended shows "Not recommended"',
        (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(
          result: buildResult(state: FitAssessmentState.notRecommended),
        ),
      ));
      expect(find.text('Not recommended'), findsOneWidget);
    });

    testWidgets('incomplete profile shows nudge',
        (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(
          result: buildResult(
            state: FitAssessmentState.incompleteProfile,
            missing: ['age', 'sex', 'goals'],
          ),
        ),
      ));
      expect(find.text('Complete profile'), findsOneWidget);
    });
  });

  group('PGFitScoreBadge — interaction', () {
    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(
          result: buildResult(state: FitAssessmentState.strongMatch),
          onTap: () => tapped++,
        ),
      ));
      await tester.tap(find.byType(PGFitScoreBadge));
      expect(tapped, 1);
    });
  });

  group('PGFitScoreBadge — accessibility', () {
    testWidgets('has proper Semantics label for strong match',
        (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(
          result: buildResult(
            state: FitAssessmentState.strongMatch,
            reasons: ['Strong alignment with your selected goals.'],
          ),
        ),
      ));
      expect(
        find.bySemanticsLabel(
          'Personal fit: strong match. Strong alignment with your selected goals.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('has proper Semantics label for missing profile',
        (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(
          result: buildResult(
            state: FitAssessmentState.incompleteProfile,
            missing: ['age', 'sex'],
          ),
        ),
      ));
      expect(
        find.bySemanticsLabel(
          'Personal fit: incomplete profile.',
        ),
        findsOneWidget,
      );
    });
  });
}
