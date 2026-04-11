import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/score_breakdown_card.dart';

void main() {
  Widget buildTestWidget({
    double? ingredientQuality,
    double? safetyPurity,
    double? evidenceResearch,
    double? brandTrust,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ScoreBreakdownCard(
          ingredientQuality: ingredientQuality,
          safetyPurity: safetyPurity,
          evidenceResearch: evidenceResearch,
          brandTrust: brandTrust,
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
}
