// Widget tests for StackGoalSupportCard. The widget is pure — tests drive
// it directly with synthetic CoverageReports (mirrors
// stack_safety_banner_test.dart's approach).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/stack/widgets/stack_coverage_card.dart';
import 'package:pharmaguide/services/stack/coverage_analyzer.dart';

Widget host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

const fullReport = CoverageReport(
  supported: [
    SupportedGoal(
      goalId: 'GOAL_SLEEP_QUALITY',
      goalLabel: 'Sleep Quality',
      productNames: ['Magnesium Glycinate'],
    ),
  ],
  underdosed: [
    UnderdosedNutrient(
      nutrientName: 'Vitamin D',
      detail:
          'Supplements provide about 42% of the daily reference amount. '
          'Food and drinks are not included.',
      source: UnderdosedSource.rda,
    ),
  ],
  priorityGaps: [
    PriorityNutrientGap(
      nutrientId: 'dha',
      nutrientName: 'DHA',
      detail: 'Not confirmed in your stack for prenatal coverage.',
    ),
  ],
  unaddressedGoals: [
    UnaddressedGoal(
      goalId: 'GOAL_CARDIOVASCULAR_HEART_HEALTH',
      goalLabel: 'Cardiovascular/Heart Health',
    ),
  ],
  unreplenishedDepletions: [
    UnreplenishedDepletion(
      drugDisplayName: 'Metformin',
      nutrientName: 'Vitamin B12',
    ),
  ],
  hasGoals: true,
  hasStack: true,
);

void main() {
  testWidgets('shows goal support without duplicating nutrient accounting', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const StackGoalSupportCard(report: fullReport)),
    );

    expect(find.byKey(const Key('goal-support-card')), findsOneWidget);
    expect(find.byKey(const Key('supplement-coverage-card')), findsNothing);
    expect(find.text('Is your stack supporting your goals?'), findsOneWidget);
    expect(find.text('Supplement nutrient coverage'), findsNothing);
    expect(find.byKey(const Key('coverage-supported')), findsOneWidget);
    expect(find.byKey(const Key('coverage-not-supported')), findsOneWidget);
    expect(find.byKey(const Key('coverage-supplement-review')), findsNothing);
    expect(find.text('Supported'), findsOneWidget);
    expect(find.text('Not currently supported'), findsOneWidget);
    expect(find.text('Coverage to review'), findsNothing);
    expect(find.text('Priority gaps'), findsNothing);
    expect(find.text('Underdosed'), findsNothing);
    expect(find.text('Unaddressed'), findsNothing);
  });

  testWidgets('partially supported bucket renders and expands', (tester) async {
    const report = CoverageReport(
      partiallySupported: [
        SupportedGoal(
          goalId: 'GOAL_REDUCE_STRESS_ANXIETY',
          goalLabel: 'Reduce Stress/Anxiety',
          productNames: ['Magnesium Glycinate'],
        ),
      ],
      hasGoals: true,
      hasStack: true,
    );
    await tester.pumpWidget(host(const StackGoalSupportCard(report: report)));

    expect(find.byKey(const Key('coverage-partial')), findsOneWidget);
    expect(find.text('Partially supported'), findsOneWidget);

    expect(find.text('Reduce Stress/Anxiety'), findsOneWidget);
    expect(find.textContaining('support may be limited'), findsOneWidget);
    expect(find.textContaining('below doses commonly studied'), findsNothing);
    expect(find.textContaining('effective dose'), findsNothing);
  });

  testWidgets('nonzero groups open by default and zero groups stay collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const StackGoalSupportCard(report: fullReport)),
    );

    expect(find.text('Sleep Quality'), findsOneWidget);
    expect(find.text('Supported by Magnesium Glycinate.'), findsOneWidget);
    expect(
      find.text(
        'No current product meets the evidence criteria for this goal.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Metformin may lower Vitamin B12'),
      findsNothing,
      reason: 'Medication guidance belongs only in Medication & nutrients.',
    );
  });

  testWidgets('hedge line renders when coverageIncomplete', (tester) async {
    const report = CoverageReport(
      hasGoals: true,
      hasStack: true,
      coverageIncomplete: true,
    );
    await tester.pumpWidget(host(const StackGoalSupportCard(report: report)));
    expect(find.byKey(const Key('coverage-hedge-line')), findsOneWidget);
    expect(
      find.textContaining("Some labels couldn't be fully analyzed"),
      findsOneWidget,
    );
  });

  testWidgets('no hedge line when coverage is complete', (tester) async {
    await tester.pumpWidget(
      host(const StackGoalSupportCard(report: fullReport)),
    );
    expect(find.byKey(const Key('coverage-hedge-line')), findsNothing);
  });

  testWidgets('no goals → invitation only; nutrients stay on Nutrients tab', (
    tester,
  ) async {
    const report = CoverageReport(
      hasGoals: false,
      hasStack: true,
      underdosed: [
        UnderdosedNutrient(
          nutrientName: 'Vitamin D',
          detail:
              'Present in your supplements, but the amount could not be '
              'compared reliably. Food and drinks are not included.',
          source: UnderdosedSource.rda,
        ),
      ],
      unreplenishedDepletions: [
        UnreplenishedDepletion(
          drugDisplayName: 'Metformin',
          nutrientName: 'Vitamin B12',
        ),
      ],
    );
    var tapped = false;
    await tester.pumpWidget(
      host(
        StackGoalSupportCard(
          report: report,
          onAddGoals: () => tapped = true,
        ),
      ),
    );
    expect(find.byKey(const Key('coverage-no-goals')), findsOneWidget);
    expect(
      find.text('Add goals to see which products support them.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('goal-support-card')), findsOneWidget);
    expect(find.byKey(const Key('supplement-coverage-card')), findsNothing);
    expect(find.byKey(const Key('coverage-supported')), findsNothing);
    expect(find.byKey(const Key('coverage-supplement-review')), findsNothing);

    await tester.tap(find.text('Add goals'));
    expect(tapped, isTrue);
  });

  testWidgets('GOAL_NONE opt-out → coverage card is hidden', (tester) async {
    const report = CoverageReport(
      hasGoals: false,
      goalsOptedOut: true,
      hasStack: true,
    );
    await tester.pumpWidget(host(const StackGoalSupportCard(report: report)));
    expect(find.byKey(const Key('coverage-no-goals')), findsNothing);
    expect(find.text('Add goals'), findsNothing);
    expect(find.byKey(const Key('goal-support-card')), findsNothing);
    expect(find.byKey(const Key('supplement-coverage-card')), findsNothing);
    expect(find.byKey(const Key('coverage-supplement-review')), findsNothing);
    expect(find.byType(StackGoalSupportCard), findsOneWidget);
    expect(find.text('Is your stack supporting your goals?'), findsNothing);
  });

  testWidgets('empty stack → card hidden entirely', (tester) async {
    const report = CoverageReport();
    await tester.pumpWidget(host(const StackGoalSupportCard(report: report)));
    expect(find.text('Is your stack supporting your goals?'), findsNothing);
    expect(find.byType(Container), findsNothing);
  });
}
