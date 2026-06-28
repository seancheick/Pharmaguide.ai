import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_timing_advice_card.dart';

void main() {
  testWidgets('PGTimingAdviceCard lays out inside a scrollable stack list', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: PGTimingAdviceCard(
                  optimizations: [
                    TimingOptimization(
                      ruleId: 'timing_magnesium_food',
                      ingredient1: 'magnesium',
                      ingredient2: '',
                      advice: 'Take magnesium with a meal',
                      ruleType: TimingRuleType.takeWithFood,
                      scoreImpact: 0,
                      evidenceLevel: EvidenceLevel.theoretical,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Timing guidance'), findsOneWidget);
    expect(
      find.text(
        'When to take items in your stack for better spacing or absorption.',
      ),
      findsOneWidget,
    );
    expect(find.text('Take magnesium with a meal'), findsOneWidget);
  });

  testWidgets('time-of-day advice is shown inline instead of check details', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PGTimingAdviceCard(
              optimizations: [
                TimingOptimization(
                  ruleId: 'timing_magnesium_evening',
                  ingredient1: 'magnesium',
                  ingredient2: 'sleep',
                  advice:
                      'Take magnesium in the evening — it supports muscle '
                      'relaxation and sleep quality.',
                  mechanism:
                      'Evening dosing is a practical recommendation based on '
                      'limited sleep-quality evidence.',
                  ruleType: TimingRuleType.timeOfDay,
                  scoreImpact: 0,
                  evidenceLevel: EvidenceLevel.theoretical,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Best time for'), findsNothing);
    expect(find.textContaining('check details'), findsNothing);
    expect(
      find.textContaining('Take magnesium in the evening'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Evening dosing is a practical recommendation'),
      findsOneWidget,
    );
  });

  testWidgets('separation advice keeps hours visible with inline reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PGTimingAdviceCard(
              optimizations: [
                TimingOptimization(
                  ruleId: 'timing_iron_magnesium_separate',
                  ingredient1: 'iron',
                  ingredient2: 'magnesium',
                  advice:
                      'Take iron and magnesium at least 2 hours apart — '
                      'magnesium can reduce non-heme iron absorption.',
                  mechanism:
                      'Magnesium at high supplemental doses may interfere '
                      'with non-heme iron absorption.',
                  ruleType: TimingRuleType.separate,
                  separationHours: 2,
                  scoreImpact: -1,
                  evidenceLevel: EvidenceLevel.theoretical,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Take iron and magnesium'), findsOneWidget);
    expect(find.textContaining('Keep at least 2h apart'), findsOneWidget);
    expect(
      find.textContaining('Magnesium at high supplemental doses'),
      findsOneWidget,
    );
  });
}
