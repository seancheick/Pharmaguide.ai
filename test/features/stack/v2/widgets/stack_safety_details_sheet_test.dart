import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/features/stack/v2/widgets/stack_safety_details_sheet.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';

void main() {
  testWidgets('renders one accessible row for every ordered warning', (
    tester,
  ) async {
    const report = StackSafetyReport(
      stackInteractions: [
        InteractionResult(
          id: 'SSI_TEST',
          type: InteractionType.supplementSupplement,
          severity: Severity.caution,
          evidenceLevel: EvidenceLevel.established,
          agent1Name: 'Iron',
          agent2Name: 'Calcium',
          mechanism: 'May reduce iron absorption.',
          management: 'Take them at different meals.',
          doseDependant: false,
          doseThreshold: null,
          sourceUrls: [],
          source: InteractionSource.pipeline,
        ),
      ],
      nutrientStatuses: [
        NutrientStatus(
          total: NutrientTotal(
            canonicalId: 'vitamin_d',
            displayName: 'Vitamin D',
            totalAmount: 125,
            unit: 'mcg',
            contributions: [
              NutrientContribution(
                stackEntryId: 'one',
                productName: 'O.N.E.',
                amount: 50,
                unit: 'mcg',
              ),
              NutrientContribution(
                stackEntryId: 'calcium-k-d',
                productName: 'Calcium K/D',
                amount: 75,
                unit: 'mcg',
              ),
            ],
          ),
          tier: NutrientTier.exceedsUl,
          ul: 100,
          pctOfUl: 125,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StackSafetyDetailsSheet(report: report)),
      ),
    );

    expect(find.text('REVIEW 2 SIGNALS'), findsOneWidget);
    expect(find.byKey(const Key('stack-safety-signal-0')), findsOneWidget);
    expect(find.byKey(const Key('stack-safety-signal-1')), findsOneWidget);
    expect(find.text('Upper limit - Vitamin D'), findsOneWidget);
    expect(find.textContaining('125 mcg/day'), findsOneWidget);
  });
}
