import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/score_breakdown_section.dart';

void main() {
  Widget buildTestWidget({
    double? ingredientQuality,
    double? safetyPurity,
    double? evidenceResearch,
    double? brandTrust,
    double? heroScore,
    double? mappedCoverage,
    bool hasThirdPartyTesting = false,
    bool isTrustedManufacturer = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: buildScoreBreakdownSection(
          ingredientQuality: ingredientQuality,
          safetyPurity: safetyPurity,
          evidenceResearch: evidenceResearch,
          brandTrust: brandTrust,
          hasThirdPartyTesting: hasThirdPartyTesting,
          isTrustedManufacturer: isTrustedManufacturer,
          heroScore: heroScore,
          mappedCoverage: mappedCoverage,
        ),
      ),
    );
  }

  group('Score breakdown section', () {
    testWidgets('header reads "Why this scored {N}" when heroScore present', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(heroScore: 84));

      expect(find.text('Why this scored 84'), findsOneWidget);
      expect(find.text('Product Analysis'), findsNothing);
    });

    testWidgets('header omits the number when heroScore is null', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Why this scored'), findsOneWidget);
    });

    testWidgets('renders locked pillar labels in order', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Ingredient Quality'), findsOneWidget);
      expect(find.text('Safety & Purity'), findsOneWidget);
      expect(find.text('Evidence & Research'), findsOneWidget);
      expect(find.text('Transparency & Verification'), findsOneWidget);
      expect(find.text('Brand trust'), findsNothing);
    });

    testWidgets('normalizes each pillar to the v2 0-10 display scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          ingredientQuality: 20.5,
          safetyPurity: 28,
          evidenceResearch: 15,
          brandTrust: 4,
        ),
      );

      expect(find.text('8/10'), findsNWidgets(3));
      expect(find.text('9/10'), findsOneWidget);
      expect(find.text('20.5/25'), findsNothing);
      expect(find.text('4.0/5'), findsNothing);
    });

    testWidgets('shows "No data" for null pillar scores', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('No data'), findsNWidgets(4));
    });

    testWidgets('reveals micro-explanation and badges when tapped', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(safetyPurity: 28, hasThirdPartyTesting: true),
      );

      await tester.tap(find.text('Safety & Purity'));
      await tester.pumpAndSettle();

      expect(
        find.text('Free from harmful ingredients and contaminants'),
        findsOneWidget,
      );
      expect(find.text('Third-party tested'), findsOneWidget);
    });

    testWidgets('coverage 0.92 shows percentage and high-confidence copy', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.92));

      expect(find.text('92%'), findsOneWidget);
      expect(find.textContaining('high-confidence'), findsOneWidget);
    });

    testWidgets('coverage 0.5 shows percentage and partial-coverage copy', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.5));

      expect(find.text('50%'), findsOneWidget);
      expect(find.textContaining('partial coverage'), findsOneWidget);
    });

    testWidgets('coverage 0.15 shows percentage and limited-data copy', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 0.15));

      expect(find.text('15%'), findsOneWidget);
      expect(find.textContaining('Limited data'), findsOneWidget);
    });

    testWidgets('coverage clamps out-of-range values to 100%', (tester) async {
      await tester.pumpWidget(buildTestWidget(mappedCoverage: 1.5));

      expect(find.text('100%'), findsOneWidget);
      expect(find.text('150%'), findsNothing);
    });

    testWidgets('coverage line hidden when mappedCoverage is null', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(ingredientQuality: 20));

      expect(find.textContaining('database'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });
  });
}
