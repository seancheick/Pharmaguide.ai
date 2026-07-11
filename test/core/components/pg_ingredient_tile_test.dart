import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/core/components/pg_ingredient_tile.dart';
import 'package:pharmaguide/features/product_detail/widgets/ingredient_explain_model.dart';

Widget _wrap(PGActiveIngredient ingredient) => MaterialApp(
  home: Scaffold(body: PGActiveIngredientTile(ingredient: ingredient)),
);

void main() {
  testWidgets('preserves the form-label casing verbatim (never lowercased)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PGActiveIngredient(
          name: 'EPA',
          formLabel: 'as Ethyl Esters',
          formQuality: FormQuality.excellent,
        ),
      ),
    );

    expect(find.text('as Ethyl Esters'), findsOneWidget);
    expect(find.text('as ethyl esters'), findsNothing);
  });

  testWidgets('form chip renders the explicit "{tier} form" label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PGActiveIngredient(
          name: 'Magnesium',
          formQuality: FormQuality.excellent,
        ),
      ),
    );

    expect(find.text('Excellent form'), findsOneWidget);
  });

  testWidgets('identity-review row shows the review note and hides every '
      'form/dose/safety claim', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PGActiveIngredient(
          name: 'Marine Lipid Concentrate',
          identityNeedsReview: true,
          // Even if a stale typed model still carries claims, the tile must
          // suppress them all when the identity needs review.
          formLabel: 'as Ethyl Esters',
          dose: '660 mg',
          formQuality: FormQuality.excellent,
          doseCallOut: DoseCallOut.high,
          isSafetyConcern: true,
        ),
      ),
    );

    expect(find.text('Marine Lipid Concentrate'), findsOneWidget);
    expect(find.text('Identity needs review'), findsOneWidget);
    expect(find.text('Excellent form'), findsNothing);
    expect(find.text('High dose'), findsNothing);
    expect(find.text('Safety concern'), findsNothing);
    expect(find.text('as Ethyl Esters'), findsNothing);
    expect(find.text('660 mg'), findsNothing);
  });
}
