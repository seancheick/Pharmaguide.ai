import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/excipient_density_section.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  test('excipientDensityLabel returns correct labels', () {
    expect(excipientDensityLabel(10, 0), 'Minimal fillers');
    expect(excipientDensityLabel(5, 3), 'Moderate fillers');
    expect(excipientDensityLabel(3, 8), 'High filler load');
  });

  testWidgets('renders nothing when both ingredient lists are empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        buildExcipientDensitySection(
          activeIngredients: const [],
          inactiveIngredients: const [],
          dosageForm: null,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Formulation purity'), findsNothing);
  });

  testWidgets('renders when a non-whitelisted excipient is present', (
    tester,
  ) async {
    // Sucralose is not whitelisted — card must render so the user sees
    // the filler ratio. (Gelatin alone would now be hidden under T0.5
    // rules; the test's intent is "renders when there's content to
    // surface", so the data is non-whitelisted.)
    await tester.pumpWidget(
      wrap(
        buildExcipientDensitySection(
          activeIngredients: const [
            {'name': 'Magnesium', 'quantity': 200, 'unit': 'mg'},
            {'name': 'Vitamin D', 'quantity': 1000, 'unit': 'IU'},
          ],
          inactiveIngredients: const [
            {'name': 'Sucralose'},
          ],
          dosageForm: null,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Formulation purity'), findsOneWidget);
    expect(find.text('2 active'), findsOneWidget);
    expect(find.text('1 filler'), findsOneWidget);
  });

  testWidgets('shows correct density label for high filler load', (
    tester,
  ) async {
    final inactives = List.generate(
      10,
      (i) => <String, dynamic>{'name': 'Filler $i'},
    );
    await tester.pumpWidget(
      wrap(
        buildExcipientDensitySection(
          activeIngredients: const [
            {'name': 'Vitamin C', 'quantity': 500, 'unit': 'mg'},
          ],
          inactiveIngredients: inactives,
          dosageForm: null,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('High filler load'), findsOneWidget);
  });

  group('T0.5 Phase 1 — whitelist + dosage-form awareness + hide-when-clean', () {
    testWidgets(
      'KSM-66 capsule (1 active + 3 standard fillers) → card hidden',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            buildExcipientDensitySection(
              activeIngredients: const [
                {'name': 'Ashwagandha (KSM-66)', 'quantity': 600, 'unit': 'mg'},
              ],
              inactiveIngredients: const [
                {'name': 'Vegetable Cellulose'},
                {'name': 'Magnesium Stearate'},
                {'name': 'Silicon Dioxide'},
              ],
              dosageForm: 'Vegetable Capsule',
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Formulation purity'), findsNothing);
      },
    );

    testWidgets('Multivitamin tablet with sucralose + dye → card visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          buildExcipientDensitySection(
            activeIngredients: const [
              {'name': 'Vitamin C', 'quantity': 500, 'unit': 'mg'},
              {'name': 'Vitamin D', 'quantity': 1000, 'unit': 'IU'},
            ],
            inactiveIngredients: const [
              {'name': 'Microcrystalline Cellulose'},
              {'name': 'Sucralose'},
              {'name': 'FD&C Red 40'},
            ],
            dosageForm: 'Tablet',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Formulation purity'), findsOneWidget);
      // "Minimal fillers" would be wrong here — must surface at least Moderate.
      expect(find.text('Minimal fillers'), findsNothing);
    });

    testWidgets(
      'Powder with 2 fillers → card visible (exceeds allowance of 1)',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            buildExcipientDensitySection(
              activeIngredients: const [
                {'name': 'Whey Protein', 'quantity': 25, 'unit': 'g'},
              ],
              inactiveIngredients: const [
                {'name': 'Microcrystalline Cellulose'},
                {'name': 'Silicon Dioxide'},
              ],
              dosageForm: 'Powder',
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Formulation purity'), findsOneWidget);
      },
    );

    testWidgets('Empty inactive list → card hidden (existing behavior)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          buildExcipientDensitySection(
            activeIngredients: const [
              {'name': 'Magnesium Glycinate', 'quantity': 200, 'unit': 'mg'},
            ],
            inactiveIngredients: const [],
            dosageForm: 'Capsule',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Formulation purity'), findsNothing);
    });

    testWidgets(
      'Capsule with 5 whitelisted fillers → visible (over allowance)',
      (tester) async {
        // Capsule allowance is 4. Five whitelisted entries = visible.
        await tester.pumpWidget(
          wrap(
            buildExcipientDensitySection(
              activeIngredients: const [
                {
                  'name': 'Multivitamin Blend',
                  'quantity': 1,
                  'unit': 'serving',
                },
              ],
              inactiveIngredients: const [
                {'name': 'Gelatin'},
                {'name': 'Magnesium Stearate'},
                {'name': 'Silicon Dioxide'},
                {'name': 'Microcrystalline Cellulose'},
                {'name': 'Dicalcium Phosphate'},
              ],
              dosageForm: 'Capsule',
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Formulation purity'), findsOneWidget);
      },
    );

    testWidgets('Gummy with whitelisted-only fillers → still visible '
        '(sugars/dyes inherent — always render)', (tester) async {
      await tester.pumpWidget(
        wrap(
          buildExcipientDensitySection(
            activeIngredients: const [
              {'name': 'Vitamin D3', 'quantity': 1000, 'unit': 'IU'},
            ],
            inactiveIngredients: const [
              {'name': 'Gelatin'},
            ],
            dosageForm: 'Gummy',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Formulation purity'), findsOneWidget);
    });

    testWidgets('Unknown dosage form falls back to capsule-like behavior', (
      tester,
    ) async {
      // Unknown form + 1 whitelisted excipient → hidden (allowance 4).
      await tester.pumpWidget(
        wrap(
          buildExcipientDensitySection(
            activeIngredients: const [
              {'name': 'Zinc', 'quantity': 15, 'unit': 'mg'},
            ],
            inactiveIngredients: const [
              {'name': 'Gelatin'},
            ],
            // dosageForm omitted → DosageForm.unknown
            dosageForm: null,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Formulation purity'), findsNothing);
    });

    testWidgets(
      'Whitelist matching is case-insensitive + tolerates whitespace',
      (tester) async {
        // Same KSM-66 scenario but with sloppy casing.
        await tester.pumpWidget(
          wrap(
            buildExcipientDensitySection(
              activeIngredients: const [
                {'name': 'Ashwagandha', 'quantity': 600, 'unit': 'mg'},
              ],
              inactiveIngredients: const [
                {'name': '  GELATIN '},
                {'name': 'magnesium stearate'},
              ],
              dosageForm: 'capsule',
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Formulation purity'), findsNothing);
      },
    );
  });
}
