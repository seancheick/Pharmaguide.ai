import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/widgets/excipient_density_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  test('ExcipientDensityCard.densityLabel returns correct labels', () {
    expect(ExcipientDensityCard.densityLabel(10, 0), 'Minimal fillers');
    expect(ExcipientDensityCard.densityLabel(5, 3), 'Moderate fillers');
    expect(ExcipientDensityCard.densityLabel(3, 8), 'High filler load');
  });

  testWidgets('renders nothing when both ingredient lists are empty',
      (tester) async {
    await tester.pumpWidget(wrap(const ExcipientDensityCard(
      activeIngredients: [],
      inactiveIngredients: [],
    )));
    await tester.pump();
    expect(find.text('Formulation Purity'), findsNothing);
  });

  testWidgets('renders when active ingredients present', (tester) async {
    await tester.pumpWidget(wrap(const ExcipientDensityCard(
      activeIngredients: [
        {'name': 'Magnesium', 'quantity': 200, 'unit': 'mg'},
        {'name': 'Vitamin D', 'quantity': 1000, 'unit': 'IU'},
      ],
      inactiveIngredients: [
        {'name': 'Gelatin'},
      ],
    )));
    await tester.pump();
    expect(find.text('Formulation Purity'), findsOneWidget);
    expect(find.text('2 active'), findsOneWidget);
    expect(find.text('1 filler'), findsOneWidget);
  });

  testWidgets('shows correct density label for high filler load',
      (tester) async {
    final inactives =
        List.generate(10, (i) => <String, dynamic>{'name': 'Filler $i'});
    await tester.pumpWidget(wrap(ExcipientDensityCard(
      activeIngredients: const [
        {'name': 'Vitamin C', 'quantity': 500, 'unit': 'mg'},
      ],
      inactiveIngredients: inactives,
    )));
    await tester.pump();
    expect(find.text('High filler load'), findsOneWidget);
  });
}
