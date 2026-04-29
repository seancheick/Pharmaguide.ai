import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/score_breakdown_card.dart';

void main() {
  Widget buildTestWidget({
    double? ingredientQuality,
    double? safetyPurity,
    double? evidenceResearch,
    double? brandTrust,
    double? heroScore,
    double? mappedCoverage,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ScoreBreakdownCard(
          ingredientQuality: ingredientQuality,
          safetyPurity: safetyPurity,
          evidenceResearch: evidenceResearch,
          brandTrust: brandTrust,
          heroScore: heroScore,
          mappedCoverage: mappedCoverage,
        ),
      ),
    );
  }

  group('ScoreBreakdownCard', () {
    testWidgets('shows all 4 section labels', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Ingredient quality'), findsOneWidget);
      expect(find.text('Safety & purity'), findsOneWidget);
      expect(find.text('Evidence & research'), findsOneWidget);
      expect(find.text('Brand trust'), findsOneWidget);
    });

    testWidgets('shows score values when provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ingredientQuality: 20.5,
        safetyPurity: 28.0,
        evidenceResearch: 15.0,
        brandTrust: 4.0,
      ));
      await tester.pumpAndSettle();

      expect(find.text('20.5/25'), findsOneWidget);
      expect(find.text('28.0/30'), findsOneWidget);
      expect(find.text('15.0/20'), findsOneWidget);
      expect(find.text('4.0/5'), findsOneWidget);
    });

    testWidgets('shows dashes when scores are null', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('—/25'), findsOneWidget);
      expect(find.text('—/30'), findsOneWidget);
      expect(find.text('—/20'), findsOneWidget);
      expect(find.text('—/5'), findsOneWidget);
    });

    testWidgets('renders 4 progress bars', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ingredientQuality: 20.0,
        safetyPurity: 25.0,
        evidenceResearch: 10.0,
        brandTrust: 3.0,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNWidgets(4));
    });
  });

  // T1.4 — hero continuity label + coverage line.

  group('ScoreBreakdownCard — T1.4 hero continuity label', () {
    testWidgets('renders "Your <X> breaks down as:" when heroScore provided',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ingredientQuality: 20.0,
        safetyPurity: 25.0,
        evidenceResearch: 10.0,
        brandTrust: 3.0,
        heroScore: 82,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Your 82 breaks down as:'), findsOneWidget);
    });

    testWidgets('rounds heroScore to nearest int (87.6 → "Your 88")',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(heroScore: 87.6));
      await tester.pumpAndSettle();

      expect(find.text('Your 88 breaks down as:'), findsOneWidget);
      expect(find.text('Your 87 breaks down as:'), findsNothing);
    });

    testWidgets('continuity label hidden when heroScore is null',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ingredientQuality: 20.0,
        safetyPurity: 25.0,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('breaks down as:'), findsNothing);
    });
  });

  group('ScoreBreakdownCard — T1.4 coverage line', () {
    testWidgets('coverage 0.92 → green tier + "high-confidence" descriptor',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.92));
      await tester.pumpAndSettle();

      expect(find.text('92%'), findsOneWidget);
      expect(find.text('Coverage'), findsOneWidget);
      expect(
        find.textContaining('high-confidence'),
        findsOneWidget,
      );
    });

    testWidgets('coverage 0.7 (boundary) → green tier', (tester) async {
      // The threshold is `>= 0.7` for the green tier — 0.7 exactly
      // should land green, not yellow.
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.7));
      await tester.pumpAndSettle();

      expect(find.text('70%'), findsOneWidget);
      expect(find.textContaining('high-confidence'), findsOneWidget);
    });

    testWidgets(
      'coverage 0.5 → yellow tier + "partial coverage" descriptor',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.5));
        await tester.pumpAndSettle();

        expect(find.text('50%'), findsOneWidget);
        expect(find.textContaining('partial coverage'), findsOneWidget);
      },
    );

    testWidgets('coverage 0.3 (boundary) → yellow tier', (tester) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.3));
      await tester.pumpAndSettle();

      expect(find.text('30%'), findsOneWidget);
      expect(find.textContaining('partial coverage'), findsOneWidget);
    });

    testWidgets(
      'coverage 0.15 → red/insufficient tier + "Limited data" descriptor',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.15));
        await tester.pumpAndSettle();

        expect(find.text('15%'), findsOneWidget);
        expect(find.textContaining('Limited data'), findsOneWidget);
      },
    );

    testWidgets('coverage 0.0 → renders 0% in the limited tier',
        (tester) async {
      // Defensive: a no-mapping product still renders the coverage
      // row so the user knows we tried (and got nothing). The hero's
      // verdict / "Not Scored" copy carries the actual messaging.
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.0));
      await tester.pumpAndSettle();

      expect(find.text('0%'), findsOneWidget);
      expect(find.textContaining('Limited data'), findsOneWidget);
    });

    testWidgets(
      'coverage 1.5 (out of range) clamps to 100% — defensive',
      (tester) async {
        // Pipeline drift could ship a >1 ratio if mapped > total.
        // Don't render "150%" — clamp.
        await tester.pumpWidget(buildTestWidget(mappedCoverage: 1.5));
        await tester.pumpAndSettle();

        expect(find.text('100%'), findsOneWidget);
        expect(find.text('150%'), findsNothing);
      },
    );

    testWidgets('coverage line hidden when mappedCoverage is null',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        ingredientQuality: 20.0,
        safetyPurity: 25.0,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Coverage'), findsNothing);
      expect(find.textContaining('database'), findsNothing);
    });
  });

  group('ScoreBreakdownCard — T1.4 integration (continuity + coverage)', () {
    testWidgets(
      'both heroScore and mappedCoverage render together at correct positions',
      (tester) async {
        // Same product, both signals present — verify both render and
        // the continuity label sits ABOVE the coverage line.
        await tester.pumpWidget(buildTestWidget(
          ingredientQuality: 22.0,
          safetyPurity: 28.0,
          evidenceResearch: 16.0,
          brandTrust: 4.0,
          heroScore: 82,
          mappedCoverage: 0.85,
        ));
        await tester.pumpAndSettle();

        expect(find.text('Your 82 breaks down as:'), findsOneWidget);
        expect(find.text('85%'), findsOneWidget);
        expect(find.text('Coverage'), findsOneWidget);

        // Y-position assertion: continuity label is above the coverage
        // row.
        final continuityY = tester
            .getTopLeft(find.text('Your 82 breaks down as:'))
            .dy;
        final coverageY = tester.getTopLeft(find.text('Coverage')).dy;
        expect(continuityY, lessThan(coverageY));
      },
    );
  });
}
