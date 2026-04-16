import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/form_absorption_section.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  final twoIngredients = [
    {'name': 'Magnesium Glycinate', 'form': 'glycinate', 'bio_score': 15},
    {'name': 'Magnesium Oxide', 'form': 'oxide', 'bio_score': 2},
  ];

  test('FormAbsorptionSection.bioLabel returns correct labels', () {
    expect(FormAbsorptionSection.bioLabel(15), 'Excellent');
    expect(FormAbsorptionSection.bioLabel(10), 'Good');
    expect(FormAbsorptionSection.bioLabel(5), 'Fair');
    expect(FormAbsorptionSection.bioLabel(2), 'Poor');
  });

  testWidgets('renders nothing when fewer than 2 ingredients have bio_score',
      (tester) async {
    await tester.pumpWidget(wrap(const FormAbsorptionSection(ingredients: [
      {'name': 'Vitamin C', 'form': 'ascorbic acid'},
    ])));
    await tester.pump();
    expect(find.byType(FormAbsorptionSection), findsOneWidget);
    expect(find.text('Form & Absorption'), findsNothing);
  });

  testWidgets(
      'renders section title and ingredient names when 2+ have bio_score',
      (tester) async {
    await tester
        .pumpWidget(wrap(FormAbsorptionSection(ingredients: twoIngredients)));
    await tester.pump();
    expect(find.text('Form & Absorption'), findsOneWidget);
    expect(find.text('Magnesium Glycinate'), findsOneWidget);
    expect(find.text('Magnesium Oxide'), findsOneWidget);
  });

  testWidgets('ranks highest bio_score first', (tester) async {
    await tester
        .pumpWidget(wrap(FormAbsorptionSection(ingredients: twoIngredients)));
    await tester.pump();
    final glycinatePos =
        tester.getTopLeft(find.text('Magnesium Glycinate')).dy;
    final oxidePos = tester.getTopLeft(find.text('Magnesium Oxide')).dy;
    expect(glycinatePos, lessThan(oxidePos));
  });

  testWidgets('renders correct bio label for each tier', (tester) async {
    await tester
        .pumpWidget(wrap(FormAbsorptionSection(ingredients: twoIngredients)));
    await tester.pump();
    expect(find.text('Excellent'), findsOneWidget);
    expect(find.text('Poor'), findsOneWidget);
  });
}
