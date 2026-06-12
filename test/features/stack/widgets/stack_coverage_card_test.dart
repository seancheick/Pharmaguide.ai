// Widget tests for StackCoverageCard. The widget is pure — tests drive
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
      detail: 'About 42% of the typical daily target across your stack.',
      source: UnderdosedSource.rda,
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
  testWidgets('renders all three buckets with counts', (tester) async {
    await tester.pumpWidget(host(const StackCoverageCard(report: fullReport)));

    expect(find.text('Is your stack working?'), findsOneWidget);
    expect(find.byKey(const Key('coverage-supported')), findsOneWidget);
    expect(find.byKey(const Key('coverage-underdosed')), findsOneWidget);
    expect(find.byKey(const Key('coverage-unaddressed')), findsOneWidget);
    expect(find.text('Supported'), findsOneWidget);
    expect(find.text('Underdosed'), findsOneWidget);
    expect(find.text('Unaddressed'), findsOneWidget);
    // Counts: 1 supported, 1 underdosed, 2 unaddressed (goal + depletion).
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('expanding a section reveals its rows', (tester) async {
    await tester.pumpWidget(host(const StackCoverageCard(report: fullReport)));

    // Collapsed by default.
    expect(find.text('Sleep Quality'), findsNothing);

    await tester.tap(find.text('Supported'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep Quality'), findsOneWidget);
    expect(find.text('Covered by Magnesium Glycinate.'), findsOneWidget);

    await tester.tap(find.text('Unaddressed'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Worth a conversation with your doctor'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Nothing in your stack currently supports your '
        'cardiovascular/heart health goal',
      ),
      findsOneWidget,
    );
  });

  testWidgets('hedge line renders when coverageIncomplete', (tester) async {
    const report = CoverageReport(
      hasGoals: true,
      hasStack: true,
      coverageIncomplete: true,
    );
    await tester.pumpWidget(host(const StackCoverageCard(report: report)));
    expect(find.byKey(const Key('coverage-hedge-line')), findsOneWidget);
    expect(
      find.textContaining("Some labels couldn't be fully analyzed"),
      findsOneWidget,
    );
  });

  testWidgets('no hedge line when coverage is complete', (tester) async {
    await tester.pumpWidget(host(const StackCoverageCard(report: fullReport)));
    expect(find.byKey(const Key('coverage-hedge-line')), findsNothing);
  });

  testWidgets('no goals → invitation ALONGSIDE goal-independent sections '
      '(depletion/underdosed gaps are not goal-gated)', (tester) async {
    const report = CoverageReport(
      hasGoals: false,
      hasStack: true,
      underdosed: [
        UnderdosedNutrient(
          nutrientName: 'Vitamin D',
          detail:
              'Present in your stack, but below the typical daily '
              'target.',
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
      host(StackCoverageCard(report: report, onAddGoals: () => tapped = true)),
    );
    expect(find.byKey(const Key('coverage-no-goals')), findsOneWidget);
    expect(
      find.text('Add goals to your profile to see what your stack covers.'),
      findsOneWidget,
    );
    // Goal bucket hidden, goal-independent buckets still rendered.
    expect(find.byKey(const Key('coverage-supported')), findsNothing);
    expect(find.byKey(const Key('coverage-underdosed')), findsOneWidget);
    expect(find.byKey(const Key('coverage-unaddressed')), findsOneWidget);

    await tester.tap(find.text('Add goals'));
    expect(tapped, isTrue);
  });

  testWidgets('GOAL_NONE opt-out → no "Add goals" nag, sections still render', (
    tester,
  ) async {
    const report = CoverageReport(
      hasGoals: false,
      goalsOptedOut: true,
      hasStack: true,
    );
    await tester.pumpWidget(host(const StackCoverageCard(report: report)));
    expect(find.byKey(const Key('coverage-no-goals')), findsNothing);
    expect(find.text('Add goals'), findsNothing);
    expect(find.byKey(const Key('coverage-underdosed')), findsOneWidget);
    expect(find.byKey(const Key('coverage-unaddressed')), findsOneWidget);
  });

  testWidgets('empty stack → card hidden entirely', (tester) async {
    const report = CoverageReport();
    await tester.pumpWidget(host(const StackCoverageCard(report: report)));
    expect(find.text('Is your stack working?'), findsNothing);
    expect(find.byType(Container), findsNothing);
  });
}
