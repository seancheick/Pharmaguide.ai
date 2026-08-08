// Characterization + migration contract for the stack-safety details sheet
// (Workstream A, increment 4). The first group locks TODAY'S rendered row text
// so the typed-signal migration provably preserves it; the second asserts the
// intentional, PM-approved changes: disposition grouping (Needs attention / Good
// to know), a SEPARATE check-status section, and suppress exclusion.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/features/stack/v2/widgets/stack_safety_details_sheet.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

InteractionResult _ix({
  required String id,
  required String a1,
  required String a2,
  Severity severity = Severity.caution,
  Severity? curated,
  String management = 'monitor closely',
  String? alertStyle,
  InteractionSource source = InteractionSource.pipeline,
}) => InteractionResult(
  id: id,
  type: InteractionType.drugSupplement,
  severity: severity,
  evidenceLevel: EvidenceLevel.established,
  agent1Name: a1,
  agent2Name: a2,
  mechanism: 'mechanism text',
  management: management,
  doseDependant: false,
  doseThreshold: null,
  sourceUrls: const [],
  source: source,
  alertStyle: alertStyle,
  curatedSeverity: curated,
);

NutrientStatus _nut({
  String id = 'vitamin_d',
  String display = 'Vitamin D',
  NutrientTier tier = NutrientTier.exceedsUl,
  double? pctOfUl = 250,
  double totalAmount = 0,
  String unit = 'mcg',
  double? ul,
  List<NutrientContribution> contributions = const [],
}) => NutrientStatus(
  total: NutrientTotal(
    canonicalId: id,
    displayName: display,
    totalAmount: totalAmount,
    unit: unit,
    contributions: contributions,
  ),
  tier: tier,
  ul: ul,
  pctOfUl: pctOfUl,
  warning: 'w',
);

/// Representative stack: a hard interaction, a food advisory, an actionable
/// supplement interaction, and a cumulative-UL breach.
StackSafetyReport _report() => StackSafetyReport(
  medicationPairInteractions: [
    _ix(
      id: 'p1',
      a1: 'Warfarin',
      a2: 'Aspirin',
      severity: Severity.contraindicated,
    ),
  ],
  medicationInteractions: [
    _ix(
      id: 'm1',
      a1: 'Grapefruit',
      a2: 'Atorvastatin',
      severity: Severity.informational,
      curated: Severity.avoid,
      alertStyle: 'food_advisory_note',
    ),
  ],
  stackInteractions: [
    _ix(id: 's1', a1: 'Iron', a2: 'Calcium', severity: Severity.caution),
  ],
  nutrientStatuses: [_nut()],
);

Future<void> _pump(WidgetTester tester, StackSafetyReport report) {
  final snapshot = const StackIntelligenceEngine().summarizeFromReports(
    stackSize: 1,
    safetyReport: report,
    recalledReport: RecalledIngredientsReport.empty(),
    synergyReport: SynergyReport.empty(),
  );
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: StackSafetyDetailsSheet(snapshot: snapshot)),
    ),
  );
}

void main() {
  group('details sheet — rendered row text preserved (characterization)', () {
    testWidgets('family-specific row text is unchanged by the migration', (
      tester,
    ) async {
      final report = StackSafetyReport(
        stackInteractions: [
          _ix(
            id: 'SSI_TEST',
            a1: 'Iron',
            a2: 'Calcium',
            severity: Severity.caution,
            management: 'Take them at different meals.',
          ),
        ],
        nutrientStatuses: [
          _nut(
            display: 'Vitamin D',
            tier: NutrientTier.exceedsUl,
            ul: 100,
            pctOfUl: 125,
            totalAmount: 125,
            contributions: const [
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
        ],
      );
      await _pump(tester, report);

      expect(find.text('2 SAFETY SIGNALS TO REVIEW'), findsOneWidget);
      expect(find.text('Iron × Calcium'), findsOneWidget);
      expect(find.text('Take them at different meals.'), findsOneWidget);
      expect(
        find.text('SUPPLEMENT INTERACTION · STRONG EVIDENCE'),
        findsOneWidget,
      );
      expect(find.text('NUTRIENT UPPER LIMIT'), findsOneWidget);
      // Renamed 2026-08-07 — see the banner test for the rationale.
      expect(find.text('Vitamin D above upper limit'), findsOneWidget);
      expect(find.textContaining('125 mcg/day'), findsOneWidget);
    });
  });

  group('details sheet — migrated structure (disposition grouping)', () {
    testWidgets('groups into Needs attention / Good to know', (tester) async {
      await _pump(tester, _report());
      expect(find.text('NEEDS ATTENTION'), findsOneWidget);
      expect(find.text('GOOD TO KNOW'), findsOneWidget);
    });

    testWidgets('food advisory sits under Good to know, concerns under Needs '
        'attention', (tester) async {
      await _pump(tester, _report());
      final needsY = tester.getTopLeft(find.text('NEEDS ATTENTION')).dy;
      final goodY = tester.getTopLeft(find.text('GOOD TO KNOW')).dy;
      final warfarinY = tester.getTopLeft(find.text('Warfarin × Aspirin')).dy;
      final advisoryY = tester
          .getTopLeft(find.text('Grapefruit × Atorvastatin'))
          .dy;

      expect(needsY, lessThan(goodY), reason: 'Needs attention comes first');
      expect(warfarinY, greaterThan(needsY));
      expect(
        warfarinY,
        lessThan(goodY),
        reason: 'the hard interaction is a concern',
      );
      expect(
        advisoryY,
        greaterThan(goodY),
        reason: 'food advisory is never a concern',
      );
    });

    testWidgets('a suppress-disposition (safe) signal does not render', (
      tester,
    ) async {
      await _pump(
        tester,
        StackSafetyReport(
          stackInteractions: [
            _ix(
              id: 'safe1',
              a1: 'Neutral',
              a2: 'Pair',
              severity: Severity.safe,
            ),
            _ix(
              id: 'c1',
              a1: 'Iron',
              a2: 'Calcium',
              severity: Severity.caution,
            ),
          ],
        ),
      );
      expect(find.text('Neutral × Pair'), findsNothing);
      expect(find.text('Iron × Calcium'), findsOneWidget);
    });

    testWidgets('incomplete checks show a SEPARATE Check status notice', (
      tester,
    ) async {
      await _pump(
        tester,
        StackSafetyReport(
          stackInteractions: [
            _ix(
              id: 'c1',
              a1: 'Iron',
              a2: 'Calcium',
              severity: Severity.caution,
            ),
          ],
          checksIncomplete: true,
        ),
      );
      expect(find.text('CHECK STATUS'), findsOneWidget);
      expect(find.textContaining('not an all-clear'), findsOneWidget);
      // The known concern still renders — the two are not mixed.
      expect(find.text('Iron × Calcium'), findsOneWidget);
    });

    testWidgets('no Check status notice when checks are complete', (
      tester,
    ) async {
      await _pump(tester, _report());
      expect(find.text('CHECK STATUS'), findsNothing);
    });
  });
}
