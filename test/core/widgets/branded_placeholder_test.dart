import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/widgets/branded_placeholder.dart';

void main() {
  group('BrandedPlaceholder', () {
    testWidgets('compact mode renders initial letter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BrandedPlaceholder(
              productName: 'Vitamin D3',
              brand: 'Thorne',
              size: 48,
            ),
          ),
        ),
      );

      expect(find.text('V'), findsOneWidget);
    });

    testWidgets('full card mode renders product name and brand', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: BrandedPlaceholder(
                productName: 'Magnesium Glycinate',
                brand: 'Pure Encapsulations',
                formFactor: 'Capsule',
                score: 85,
                size: 160,
              ),
            ),
          ),
        ),
      );

      expect(find.text('M'), findsOneWidget);
      expect(find.text('Magnesium Glycinate'), findsOneWidget);
      expect(find.text('Pure Encapsulations'), findsOneWidget);
    });

    testWidgets('same brand produces same color across instances', (
      tester,
    ) async {
      // Build two separate BrandedPlaceholders with the same brand
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                BrandedPlaceholder(
                  productName: 'Product A',
                  brand: 'Thorne',
                  size: 48,
                ),
                BrandedPlaceholder(
                  productName: 'Product B',
                  brand: 'Thorne',
                  size: 48,
                ),
              ],
            ),
          ),
        ),
      );

      // Both containers should have the same decoration color
      final containers = tester.widgetList<Container>(find.byType(Container));
      final decorations = containers
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color != null)
          .toList();

      // There should be at least 2 colored containers (one per placeholder)
      expect(decorations.length, greaterThanOrEqualTo(2));
      // Same brand → same color
      expect(decorations[0].color, equals(decorations[1].color));
    });

    testWidgets('different brands produce different colors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                BrandedPlaceholder(
                  productName: 'Product A',
                  brand: 'Thorne',
                  size: 48,
                ),
                BrandedPlaceholder(
                  productName: 'Product B',
                  brand: 'Garden of Life',
                  size: 48,
                ),
              ],
            ),
          ),
        ),
      );

      final containers = tester.widgetList<Container>(find.byType(Container));
      final decorations = containers
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color != null)
          .toList();

      expect(decorations.length, greaterThanOrEqualTo(2));
      // Different brands → different colors
      expect(decorations[0].color, isNot(equals(decorations[1].color)));
    });

    testWidgets('form factor icon renders for known types', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BrandedPlaceholder(
              productName: 'Fish Oil',
              brand: 'Nordic Naturals',
              formFactor: 'Softgel',
              size: 160,
            ),
          ),
        ),
      );

      // Should find an Icon widget with circle_outlined (softgel mapping)
      expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
    });

    testWidgets('empty brand uses product name for color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BrandedPlaceholder(
              productName: 'Mystery Product',
              brand: '',
              size: 48,
            ),
          ),
        ),
      );

      // Should render without crash, showing the initial
      expect(find.text('M'), findsOneWidget);
    });

    testWidgets('score bar renders when score provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: BrandedPlaceholder(
                productName: 'Creatine',
                brand: 'Optimum Nutrition',
                score: 72,
                size: 160,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}
