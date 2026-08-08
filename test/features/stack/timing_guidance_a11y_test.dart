// Accessibility contract for the surfaces added in the longitudinal work.
//
// Two rules drive these: information must never be carried by an icon or a
// colour alone, and text must survive large accessibility type sizes without
// clipping the value it is reporting.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_depletion_card.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_timing_guidance_card.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/depletion_watch.dart';
import 'package:pharmaguide/services/stack/timing_guidance_builder.dart';

const _withFood = TimingOptimization(
  ruleId: 'timing_with_food',
  ingredient1: 'vitamin d',
  advice: 'Take with a meal.',
  relation: TimingRelation(type: TimingRelationType.withFood),
  category: TimingCategory.howToTake,
  actionability: TimingActionability.recommended,
  evidenceLevel: EvidenceLevel.established,
  sourceAuthority: SourceAuthority.fdaLabel,
  scoreImpact: -1,
);

const _magnesiumWithFood = TimingOptimization(
  ruleId: 'timing_magnesium_with_food',
  ingredient1: 'magnesium',
  advice:
      'Take magnesium with food to ease the loose stools or stomach upset it '
      'can cause on an empty stomach.',
  relation: TimingRelation(type: TimingRelationType.withFood),
  category: TimingCategory.howToTake,
  actionability: TimingActionability.recommended,
  evidenceLevel: EvidenceLevel.established,
  sourceAuthority: SourceAuthority.fdaLabel,
  scoreImpact: -1,
);

const _calciumSeparation = TimingOptimization(
  ruleId: 'timing_calcium_levothyroxine',
  ingredient1: 'levothyroxine',
  ingredient2: 'calcium',
  advice: 'Keep calcium at least 4 hours away from levothyroxine.',
  relation: TimingRelation(
    type: TimingRelationType.separateFrom,
    minimumHours: 4,
  ),
  category: TimingCategory.importantSeparation,
  actionability: TimingActionability.recommended,
  evidenceLevel: EvidenceLevel.established,
  sourceAuthority: SourceAuthority.fdaLabel,
  scoreImpact: -2,
  involvesMedication: true,
  medicationIsProduct1: true,
);

const _match = DepletionMatch(
  depletionId: 'DEP_METFORMIN_VITAMINB12',
  drugDisplayName: 'Metformin',
  drugClassId: '860974',
  nutrientName: 'Vitamin B12',
  nutrientCanonicalId: 'vitamin_b12',
  severity: 'significant',
  mechanism: 'Impairs B12 absorption.',
  recommendation: 'Worth a conversation with your clinician.',
  monitoringTipShort: 'Consider discussing B12 testing at your next visit.',
  citationReviewStatus: 'verified',
);

Widget _wrap(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    theme: V2Theme.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('timing guidance accessibility', () {
    testWidgets('each product name is exposed as a heading', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          const PGTimingGuidanceCard(
            guidance: TimingGuidance(
              products: [
                ProductTimingGuidance(
                  stackEntryId: 'row-d3',
                  productName: 'D3 5000 IU',
                  howToTake: [_withFood],
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.text('D3 5000 IU')),
        matchesSemantics(label: 'D3 5000 IU', isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('the medication caveat is text, not styling', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PGTimingGuidanceCard(
            guidance: TimingGuidance(
              products: [
                ProductTimingGuidance(
                  stackEntryId: 'row-cal',
                  productName: 'Calcium K/D',
                  importantSeparation: [_calciumSeparation],
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.text('Continue taking your medication exactly as prescribed.'),
        findsOneWidget,
      );
    });

    testWidgets('survives a large accessibility text size', (tester) async {
      // Dynamic Type at 2x is a supported setting, not an edge case.
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          const PGTimingGuidanceCard(
            guidance: TimingGuidance(
              products: [
                ProductTimingGuidance(
                  stackEntryId: 'row-a',
                  productName: 'Magnesium Glycinate 400mg Capsules',
                  howToTake: [_magnesiumWithFood],
                ),
              ],
            ),
          ),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('depletion watch accessibility', () {
    testWidgets('the duration line is announced, not just coloured', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PGDepletionCard(
            depletions: [_match],
            watchStatuses: {
              'DEP_METFORMIN_VITAMINB12': DepletionWatchStatus(
                depletionId: 'DEP_METFORMIN_VITAMINB12',
                thresholdDays: 730,
                basis: 'Reviewer basis.',
                trackedFor: Duration(days: 1100),
              ),
            },
          ),
        ),
      );

      // The row changes colour when due; the sentence is what makes that
      // change perceivable without colour vision.
      expect(
        find.bySemanticsLabel(RegExp('Tracked here for about 3 years')),
        findsOneWidget,
      );
    });

    testWidgets('no duration is announced when not due', (tester) async {
      await tester.pumpWidget(
        _wrap(const PGDepletionCard(depletions: [_match])),
      );

      expect(find.bySemanticsLabel(RegExp('Tracked here')), findsNothing);
    });
  });
}
