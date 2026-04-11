// Tests for NutritionPanel — the v1.3.2 nutrition hybrid widget that
// surfaces calories_per_serving (column) and the four macros packed into
// detail_blob.nutrition_detail (carbs, fat, protein, fiber).
//
// TDD: these tests describe the contract before the widget exists. Run
// them red, then implement NutritionPanel until they go green.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/nutrition_panel.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('NutritionPanel', () {
    testWidgets('renders nothing when both inputs are absent', (tester) async {
      await _pump(
        tester,
        const NutritionPanel(caloriesPerServing: null, nutritionDetail: null),
      );

      expect(find.byType(NutritionPanel), findsOneWidget);
      expect(find.text('Nutrition Facts'), findsNothing);
      expect(find.byKey(const Key('nutrition-panel-card')), findsNothing);
    });

    testWidgets('renders nothing when nutrition_detail is empty and calories null', (tester) async {
      await _pump(
        tester,
        const NutritionPanel(
          caloriesPerServing: null,
          nutritionDetail: <String, dynamic>{
            'calories_per_serving': null,
            'total_carbohydrates_g': null,
            'total_fat_g': null,
            'protein_g': null,
            'dietary_fiber_g': null,
          },
        ),
      );

      expect(find.byKey(const Key('nutrition-panel-card')), findsNothing);
    });

    testWidgets('renders calories from the column when blob is missing', (tester) async {
      await _pump(
        tester,
        const NutritionPanel(
          caloriesPerServing: 120.0,
          nutritionDetail: null,
        ),
      );

      expect(find.byKey(const Key('nutrition-panel-card')), findsOneWidget);
      expect(find.text('Nutrition Facts'), findsOneWidget);
      expect(find.text('Calories'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      // Macros not present → no rows for them.
      expect(find.text('Protein'), findsNothing);
      expect(find.text('Total Carbs'), findsNothing);
    });

    testWidgets('renders all five macros when blob has them', (tester) async {
      await _pump(
        tester,
        const NutritionPanel(
          caloriesPerServing: 15.0,
          nutritionDetail: <String, dynamic>{
            'calories_per_serving': 15.0,
            'total_carbohydrates_g': 4.0,
            'total_fat_g': 0.0,
            'protein_g': 0.5,
            'dietary_fiber_g': 1.5,
          },
        ),
      );

      expect(find.text('Nutrition Facts'), findsOneWidget);
      expect(find.text('Calories'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('Total Carbs'), findsOneWidget);
      expect(find.text('4 g'), findsOneWidget);
      expect(find.text('Total Fat'), findsOneWidget);
      // 0g should still render (it's a real value, not missing).
      expect(find.text('0 g'), findsOneWidget);
      expect(find.text('Protein'), findsOneWidget);
      expect(find.text('0.5 g'), findsOneWidget);
      expect(find.text('Dietary Fiber'), findsOneWidget);
      expect(find.text('1.5 g'), findsOneWidget);
    });

    testWidgets('skips individual macro rows when their value is null', (tester) async {
      await _pump(
        tester,
        const NutritionPanel(
          caloriesPerServing: 100.0,
          nutritionDetail: <String, dynamic>{
            'calories_per_serving': 100.0,
            'total_carbohydrates_g': null,
            'total_fat_g': 5.0,
            'protein_g': null,
            'dietary_fiber_g': null,
          },
        ),
      );

      expect(find.text('Calories'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('Total Fat'), findsOneWidget);
      expect(find.text('5 g'), findsOneWidget);
      // Skipped rows should NOT show.
      expect(find.text('Total Carbs'), findsNothing);
      expect(find.text('Protein'), findsNothing);
      expect(find.text('Dietary Fiber'), findsNothing);
    });

    testWidgets('formats whole numbers without trailing .0', (tester) async {
      await _pump(
        tester,
        const NutritionPanel(
          caloriesPerServing: 200.0,
          nutritionDetail: <String, dynamic>{
            'calories_per_serving': 200.0,
            'total_carbohydrates_g': 10.0,
            'total_fat_g': 2.5,
            'protein_g': 25.0,
            'dietary_fiber_g': null,
          },
        ),
      );

      // Whole numbers: no ".0"
      expect(find.text('200'), findsOneWidget);
      expect(find.text('10 g'), findsOneWidget);
      expect(find.text('25 g'), findsOneWidget);
      // Non-whole: keep the decimal
      expect(find.text('2.5 g'), findsOneWidget);
    });

    testWidgets('column calories takes precedence over blob calories on conflict', (tester) async {
      // Edge case: if the column and blob disagree, the column wins
      // (column is the canonical filter source; blob is for display).
      await _pump(
        tester,
        const NutritionPanel(
          caloriesPerServing: 50.0,
          nutritionDetail: <String, dynamic>{
            'calories_per_serving': 99.0, // intentionally different
            'total_carbohydrates_g': null,
            'total_fat_g': null,
            'protein_g': null,
            'dietary_fiber_g': null,
          },
        ),
      );

      expect(find.text('50'), findsOneWidget);
      expect(find.text('99'), findsNothing);
    });

    testWidgets('handles int and double values from JSON decode', (tester) async {
      // jsonDecode can produce int OR double depending on the source.
      // The widget must accept both without crashing.
      await _pump(
        tester,
        const NutritionPanel(
          caloriesPerServing: 80.0,
          nutritionDetail: <String, dynamic>{
            'calories_per_serving': 80, // int from JSON
            'total_carbohydrates_g': 12, // int
            'total_fat_g': 3.2, // double
            'protein_g': 4, // int
            'dietary_fiber_g': null,
          },
        ),
      );

      expect(find.text('80'), findsOneWidget);
      expect(find.text('12 g'), findsOneWidget);
      expect(find.text('3.2 g'), findsOneWidget);
      expect(find.text('4 g'), findsOneWidget);
    });
  });
}
