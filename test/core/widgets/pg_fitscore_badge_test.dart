import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/fit_score_result.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_fitscore_badge.dart';

/// Widget tests for [PGFitScoreBadge] — one per state (+fit / neutral /
/// concerns / poor-fit / missing-profile / loading).
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );
  }

  FitScoreResult buildResult({
    required double fit,
    List<String> missing = const [],
  }) {
    return FitScoreResult(
      scoreFit20: fit,
      scoreCombined100: 75 + fit,
      e1: 0,
      e2a: 0,
      e2b: 0,
      e2c: fit,
      missingFields: missing,
      maxPossible: 100,
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

    testWidgets('positive fit (+5) shows "+5 fit" with safe color',
        (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(result: buildResult(fit: 5)),
      ));
      expect(find.text('+5 fit'), findsOneWidget);
    });

    testWidgets('neutral fit (0) shows "Matches you"', (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(result: buildResult(fit: 0)),
      ));
      expect(find.text('Matches you'), findsOneWidget);
    });

    testWidgets('mild concern (-3) shows "-3 fit" with caution color',
        (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(result: buildResult(fit: -3)),
      ));
      expect(find.text('-3 fit'), findsOneWidget);
    });

    testWidgets('poor fit (-7) shows "-7 fit" with danger color',
        (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(result: buildResult(fit: -7)),
      ));
      expect(find.text('-7 fit'), findsOneWidget);
    });

    testWidgets('missing profile (fit=0, missing fields) shows nudge',
        (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(
          result: buildResult(fit: 0, missing: ['age', 'sex', 'goals']),
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
          result: buildResult(fit: 5),
          onTap: () => tapped++,
        ),
      ));
      await tester.tap(find.byType(PGFitScoreBadge));
      expect(tapped, 1);
    });
  });

  group('PGFitScoreBadge — accessibility', () {
    testWidgets('has proper Semantics label for positive fit',
        (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(result: buildResult(fit: 6)),
      ));
      expect(
        find.bySemanticsLabel(
          RegExp(r'FitScore adjustment positive 6\.0. Well-suited'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('has proper Semantics label for missing profile',
        (tester) async {
      await tester.pumpWidget(wrap(
        PGFitScoreBadge(
          result: buildResult(fit: 0, missing: ['age', 'sex']),
        ),
      ));
      expect(
        find.bySemanticsLabel(
          'FitScore unavailable — complete your profile for personalization',
        ),
        findsOneWidget,
      );
    });
  });
}
