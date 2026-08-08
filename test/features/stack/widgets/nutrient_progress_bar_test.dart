// Widget tests for [NutrientProgressBar].
//
// We exercise three things:
//   1. The pure [tierColorFor] mapping covers every NutrientTier.
//   2. The widget renders the nutrient name, the formatted amount,
//      and the % target / %UL subtitle.
//   3. Warning chips render when (and only when) the status carries
//      a warning string.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/features/stack/widgets/nutrient_progress_bar.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

void main() {
  group('NutrientProgressBar.tierColorFor', () {
    test('every tier maps to a non-null color', () {
      for (final tier in NutrientTier.values) {
        expect(
          NutrientProgressBar.tierColorFor(V2Palette.light, tier),
          isNotNull,
        );
      }
    });

    test('only exceedsUl is red and only approachingUl is amber', () {
      expect(
        NutrientProgressBar.tierColorFor(
          V2Palette.light,
          NutrientTier.exceedsUl,
        ),
        V2Palette.light.contraindicated,
      );
      expect(
        NutrientProgressBar.tierColorFor(
          V2Palette.light,
          NutrientTier.approachingUl,
        ),
        V2Palette.light.caution,
      );
    });

    test('high intake below the UL ceiling stays calm/green', () {
      // abundant / aboveTypical no longer carry a warning tone — multiples of
      // the RDA are not a hazard while there is headroom to the limit. Only the
      // UL story (approaching/exceeds) escalates color.
      expect(
        NutrientProgressBar.tierColorFor(
          V2Palette.light,
          NutrientTier.aboveTypical,
        ),
        V2Palette.light.safe,
      );
      expect(
        NutrientProgressBar.tierColorFor(
          V2Palette.light,
          NutrientTier.abundant,
        ),
        V2Palette.light.safe,
      );
      expect(
        NutrientProgressBar.tierColorFor(
          V2Palette.light,
          NutrientTier.adequate,
        ),
        V2Palette.light.safe,
      );
      expect(
        NutrientProgressBar.tierColorFor(
          V2Palette.light,
          NutrientTier.aboveAdequateNoUl,
        ),
        V2Palette.light.safe,
      );
    });
  });

  group('NutrientProgressBar widget rendering', () {
    testWidgets('upper-limit warning separates takeaway from explanation', (
      tester,
    ) async {
      const status = NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'vitamin_d',
          displayName: 'Vitamin D',
          totalAmount: 125,
          unit: 'mcg',
          contributions: [],
        ),
        tier: NutrientTier.exceedsUl,
        warning:
            'Above the upper limit — Sustained excessive vitamin D intake can '
            'increase the risk of hypercalcemia and kidney complications.',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NutrientProgressBar(status: status)),
        ),
      );

      expect(find.text('Above the upper limit'), findsOneWidget);
      expect(
        find.text(
          'Sustained excessive vitamin D intake can increase the risk of '
          'hypercalcemia and kidney complications.',
        ),
        findsOneWidget,
      );
      expect(find.text(status.warning!), findsNothing);
    });

    testWidgets('renders display name, amount, and target/UL subtitle', (
      tester,
    ) async {
      const status = NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'zinc',
          displayName: 'Zinc',
          totalAmount: 52,
          unit: 'mg',
          contributions: [],
        ),
        tier: NutrientTier.exceedsUl,
        rda: 11,
        ul: 40,
        pctOfRda: 472.7,
        pctOfUl: 130.0,
        warning: 'Exceeds Upper Limit — risk of copper depletion',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NutrientProgressBar(status: status)),
        ),
      );

      expect(find.text('Zinc'), findsOneWidget);
      expect(find.text('52 MG'), findsOneWidget);
      // Compact layout prefers UL over RDA when both are present — a
      // single tight row keeps the nutrient list scannable. % target only
      // shows as the fallback when there is no UL.
      expect(find.textContaining('130% UL'), findsOneWidget);
      expect(find.textContaining('copper depletion'), findsOneWidget);
    });

    testWidgets('contributions open in a bottom sheet with form context', (
      tester,
    ) async {
      const status = NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'vitamin_k',
          displayName: 'Vitamin K',
          totalAmount: 130,
          unit: 'mcg',
          contributions: [
            NutrientContribution(
              stackEntryId: 'cal-kd',
              productName: 'Calcium K/D',
              ingredientName: 'Vitamin K1',
              amount: 100,
              unit: 'mcg',
            ),
            NutrientContribution(
              stackEntryId: 'cal-kd',
              productName: 'Calcium K/D',
              ingredientName: 'Vitamin K2 (MK-7)',
              amount: 30,
              unit: 'mcg',
            ),
          ],
        ),
        tier: NutrientTier.aboveAdequateNoUl,
        rda: 120,
        pctOfRda: 108.3,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NutrientProgressBar(status: status)),
        ),
      );

      await tester.tap(find.text('Vitamin K'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Vitamin K contributors'), findsOneWidget);
      expect(find.byType(Scrollable), findsWidgets);
      expect(find.text('Calcium K/D - Vitamin K1'), findsOneWidget);
      expect(find.text('Calcium K/D - Vitamin K2 (MK-7)'), findsOneWidget);
    });

    testWidgets('omits warning chip when status has no warning', (
      tester,
    ) async {
      const status = NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'magnesium',
          displayName: 'Magnesium',
          totalAmount: 200,
          unit: 'mg',
          contributions: [],
        ),
        tier: NutrientTier.adequate,
        rda: 400,
        ul: 350,
        pctOfRda: 50,
        pctOfUl: 57.1,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NutrientProgressBar(status: status)),
        ),
      );

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('shows em-dash when both rda and ul are null', (tester) async {
      const status = NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'unknown',
          displayName: 'Unknown Nutrient',
          totalAmount: 100,
          unit: 'mg',
          contributions: [],
        ),
        tier: NutrientTier.noRda,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NutrientProgressBar(status: status)),
        ),
      );

      // Compact layout uses an em-dash as the placeholder when neither
      // RDA nor UL data is available — keeps the single-row layout tight.
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('excluded-only nutrients never render a misleading zero', (
      tester,
    ) async {
      const status = NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'magnesium',
          displayName: 'Magnesium L-Threonate',
          totalAmount: 0,
          unit: '',
          contributions: [],
          excludedContributions: [
            ExcludedNutrientContribution(
              contribution: NutrientContribution(
                stackEntryId: 'magtein',
                productName: 'Magtein',
                ingredientName: 'Magnesium L-Threonate',
                amount: 2000,
                unit: 'mg',
              ),
              reason: NutrientExclusionReason.compoundFormDuplicate,
            ),
          ],
        ),
        tier: NutrientTier.noRda,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NutrientProgressBar(status: status)),
        ),
      );

      expect(find.text('Not totaled'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(
        find.textContaining('could not be safely included'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('shows label-directed amount and target ranges', (
      tester,
    ) async {
      const status = NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'vitamin_k',
          displayName: 'Vitamin K',
          minimumTotalAmount: 130,
          totalAmount: 390,
          unit: 'mcg',
          contributions: [],
        ),
        tier: NutrientTier.aboveAdequateNoUl,
        rda: 120,
        pctOfRda: 108.3,
        maximumPctOfRda: 325,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NutrientProgressBar(status: status)),
        ),
      );

      expect(find.text('130–390 MCG'), findsOneWidget);
      expect(find.text('108–325% target'), findsOneWidget);
    });

    testWidgets('explains when a real UL cannot be calculated', (tester) async {
      const status = NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'vitamin_a',
          displayName: 'Vitamin A',
          totalAmount: 1125,
          unit: 'mcg',
          contributions: [],
        ),
        tier: NutrientTier.abundant,
        rda: 900,
        ul: 3000,
        pctOfRda: 125,
        ulAssessmentIndeterminate: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NutrientProgressBar(status: status)),
        ),
      );

      expect(find.text('125% target'), findsOneWidget);
      expect(
        find.text(
          'UL not calculated: the label does not provide enough form detail.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders unit conflict note when total has hasUnitConflict', (
      tester,
    ) async {
      const status = NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'folate',
          displayName: 'Folate',
          totalAmount: 1200,
          unit: 'mcg',
          contributions: [],
          hasUnitConflict: true,
        ),
        tier: NutrientTier.abundant,
        rda: 400,
        pctOfRda: 300,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NutrientProgressBar(status: status)),
        ),
      );

      expect(find.textContaining('different unit'), findsOneWidget);
    });

    testWidgets('formats sub-10 amounts with one decimal', (tester) async {
      const status = NutrientStatus(
        total: NutrientTotal(
          canonicalId: 'vitamin_b12',
          displayName: 'Vitamin B12',
          totalAmount: 2.4,
          unit: 'mcg',
          contributions: [],
        ),
        tier: NutrientTier.abundant,
        rda: 2.4,
        pctOfRda: 100,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NutrientProgressBar(status: status)),
        ),
      );

      expect(find.text('2.4 MCG'), findsOneWidget);
    });
  });
}
