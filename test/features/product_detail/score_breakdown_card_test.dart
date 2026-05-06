// Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md, Sprint S2.2, T14.
//
// Updated for "Product Analysis" rebuild — pillar names capitalized,
// "Brand trust" → "Transparency & Verification", scores normalized
// to 0–100, micro-explanations under each bar, hero continuity label
// deprecated.

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

  group('normalizePillarScore — pure helper (T14)', () {
    test('null raw → null', () {
      expect(normalizePillarScore(null, 25), isNull);
    });

    test('zero or negative max → null (defensive)', () {
      expect(normalizePillarScore(20, 0), isNull);
      expect(normalizePillarScore(20, -5), isNull);
    });

    test('exact max → 100', () {
      expect(normalizePillarScore(25, 25), 100);
      expect(normalizePillarScore(30, 30), 100);
    });

    test('zero raw → 0', () {
      expect(normalizePillarScore(0, 25), 0);
    });

    test('half raw → 50', () {
      expect(normalizePillarScore(12.5, 25), 50);
    });

    test('above max clamps to 100 (defensive)', () {
      expect(normalizePillarScore(30, 25), 100);
    });

    test('below 0 clamps to 0 (defensive)', () {
      expect(normalizePillarScore(-5, 25), 0);
    });

    test('rounds to nearest int (16.0/25 = 64)', () {
      expect(normalizePillarScore(16, 25), 64);
    });

    test('rounds half up (12/30 = 40, 12.5/30 → 42)', () {
      expect(normalizePillarScore(12, 30), 40);
      // 12.5/30 = 0.4166... × 100 = 41.666... → 42 with .round()
      expect(normalizePillarScore(12.5, 30), 42);
    });
  });

  group('ScoreBreakdownCard — T5 header + pillar labels', () {
    testWidgets('header reads "Why this scored {N}" when heroScore present', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(heroScore: 84));
      await tester.pumpAndSettle();
      expect(find.text('Why this scored 84'), findsOneWidget);
      // Pre-T5 headers are gone.
      expect(find.text('Product Analysis'), findsNothing);
      expect(find.text('Product Quality'), findsNothing);
    });

    testWidgets(
      'header reads "Why this scored" (no number) when heroScore null',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();
        expect(find.text('Why this scored'), findsOneWidget);
        expect(find.text('Product Analysis'), findsNothing);
      },
    );

    testWidgets('all 4 pillar labels match locked spec', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      expect(find.text('Ingredient Quality'), findsOneWidget);
      expect(find.text('Safety & Purity'), findsOneWidget);
      expect(find.text('Evidence & Research'), findsOneWidget);
      expect(find.text('Transparency & Verification'), findsOneWidget);
      // Pre-T14 lowercase + "Brand trust" labels are gone.
      expect(find.text('Ingredient quality'), findsNothing);
      expect(find.text('Brand trust'), findsNothing);
    });

    testWidgets('all 4 micro-explanations render under their pillar', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      expect(find.text('Form, dosage, and bioavailability'), findsOneWidget);
      expect(
        find.text('Free from harmful ingredients and contaminants'),
        findsOneWidget,
      );
      expect(find.text('Clinical support behind ingredients'), findsOneWidget);
      expect(
        find.text('Label clarity and independent testing'),
        findsOneWidget,
      );
    });
  });

  group('ScoreBreakdownCard — T14 normalized 0–100 scores', () {
    testWidgets('shows X/100 for each pillar (normalized)', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          ingredientQuality: 20.5, // 20.5/25 = 82
          safetyPurity: 28.0, // 28/30 ≈ 93
          evidenceResearch: 15.0, // 15/20 = 75
          brandTrust: 4.0, // 4/5 = 80
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('82/100'), findsOneWidget);
      expect(find.text('93/100'), findsOneWidget);
      expect(find.text('75/100'), findsOneWidget);
      expect(find.text('80/100'), findsOneWidget);
      // Pre-T14 raw fractions are gone.
      expect(find.text('20.5/25'), findsNothing);
      expect(find.text('4.0/5'), findsNothing);
    });

    testWidgets('shows "—/100" when scores are null', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      // 4 pillars × null score → 4 dash lines.
      expect(find.text('—/100'), findsNWidgets(4));
    });

    testWidgets('renders 4 progress bars', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          ingredientQuality: 20.0,
          safetyPurity: 25.0,
          evidenceResearch: 10.0,
          brandTrust: 3.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNWidgets(4));
    });
  });

  group('ScoreBreakdownCard — T14 deprecated hero continuity label', () {
    testWidgets(
      '"Your X breaks down as:" no longer renders even with heroScore',
      (tester) async {
        // T14 — the score lives on the hero ScoreLine now; the inline
        // continuity label was duplicate. Param kept for back-compat
        // but the label is suppressed.
        await tester.pumpWidget(buildTestWidget(heroScore: 82));
        await tester.pumpAndSettle();
        expect(find.textContaining('breaks down as:'), findsNothing);
      },
    );
  });

  group('ScoreBreakdownCard — T1.4 coverage line (still in scope)', () {
    testWidgets('coverage 0.92 → green tier + "high-confidence" descriptor', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.92));
      await tester.pumpAndSettle();
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('Coverage'), findsOneWidget);
      expect(find.textContaining('high-confidence'), findsOneWidget);
    });

    testWidgets('coverage 0.7 (boundary) → green tier', (tester) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.7));
      await tester.pumpAndSettle();
      expect(find.text('70%'), findsOneWidget);
      expect(find.textContaining('high-confidence'), findsOneWidget);
    });

    testWidgets('coverage 0.5 → yellow tier + "partial coverage" descriptor', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.5));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget);
      expect(find.textContaining('partial coverage'), findsOneWidget);
    });

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

    testWidgets('coverage 0.0 → renders 0% in the limited tier', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.0));
      await tester.pumpAndSettle();
      expect(find.text('0%'), findsOneWidget);
      expect(find.textContaining('Limited data'), findsOneWidget);
    });

    testWidgets('coverage 1.5 (out of range) clamps to 100% — defensive', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 1.5));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('150%'), findsNothing);
    });

    testWidgets('coverage line hidden when mappedCoverage is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(ingredientQuality: 20.0, safetyPurity: 25.0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Coverage'), findsNothing);
      expect(find.textContaining('database'), findsNothing);
    });
  });
}
