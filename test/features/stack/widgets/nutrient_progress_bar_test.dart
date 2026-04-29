// Widget tests for [NutrientProgressBar].
//
// We exercise three things:
//   1. The pure [tierColorFor] mapping covers every NutrientTier.
//   2. The widget renders the nutrient name, the formatted amount,
//      and the %RDA / %UL subtitle.
//   3. Warning chips render when (and only when) the status carries
//      a warning string.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/features/stack/widgets/nutrient_progress_bar.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

void main() {
  group('NutrientProgressBar.tierColorFor', () {
    test('every tier maps to a non-null color', () {
      for (final tier in NutrientTier.values) {
        expect(NutrientProgressBar.tierColorFor(tier), isNotNull);
      }
    });

    test('exceedsUl is red, approachingUl is orange', () {
      expect(
        NutrientProgressBar.tierColorFor(NutrientTier.exceedsUl),
        AppTheme.severityContraindicated,
      );
      expect(
        NutrientProgressBar.tierColorFor(NutrientTier.approachingUl),
        AppTheme.severityAvoid,
      );
    });

    test('aboveTypical is yellow, adequate is green', () {
      expect(
        NutrientProgressBar.tierColorFor(NutrientTier.aboveTypical),
        AppTheme.severityCaution,
      );
      expect(
        NutrientProgressBar.tierColorFor(NutrientTier.adequate),
        AppTheme.severitySafe,
      );
    });
  });

  group('NutrientProgressBar widget rendering', () {
    testWidgets('renders display name, amount, and RDA/UL subtitle', (
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
      // single tight row keeps the nutrient list scannable. %RDA only
      // shows as the fallback when there is no UL.
      expect(find.textContaining('130% UL'), findsOneWidget);
      expect(find.textContaining('copper depletion'), findsOneWidget);
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
