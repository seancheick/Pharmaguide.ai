// Widget tests for PGDailyPlanCard (roadmap Phase 3 surface).
//
// The card draws the resolver's arrangement. It must never present a clock
// time (the resolver's anchor hours are a scheduling device, not dosing
// advice), and must show a constraint it could not place in the pipeline's own
// words rather than dropping it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_daily_plan_card.dart';
import 'package:pharmaguide/services/stack/timing_sequence_resolver.dart';

Future<void> _pump(WidgetTester tester, TimingSequencePlan plan) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: PGDailyPlanCard(plan: plan)),
      ),
    ),
  );
}

TimingSequencePlan _plan({
  Map<DailySlot, List<String>> items = const {},
  List<UnsatisfiedTimingConstraint> unsatisfied = const [],
}) {
  return TimingSequencePlan(
    itemsBySlot: {
      for (final slot in DailySlot.values)
        slot: items[slot] ?? const <String>[],
    },
    unsatisfied: unsatisfied,
  );
}

void main() {
  testWidgets('an empty plan renders nothing', (tester) async {
    await _pump(tester, _plan());
    expect(find.byType(Card), findsNothing);
    expect(find.textContaining('One way to space'), findsNothing);
  });

  testWidgets('renders each filled slot with its items', (tester) async {
    await _pump(
      tester,
      _plan(
        items: {
          DailySlot.withBreakfast: ['iron', 'vitamin c'],
          DailySlot.bedtime: ['magnesium'],
        },
      ),
    );

    expect(find.text('With breakfast'), findsOneWidget);
    expect(find.text('iron · vitamin c'), findsOneWidget);
    expect(find.text('Before bed'), findsOneWidget);
    expect(find.text('magnesium'), findsOneWidget);
  });

  testWidgets('omits slots with nothing in them', (tester) async {
    await _pump(
      tester,
      _plan(
        items: {
          DailySlot.bedtime: ['magnesium'],
        },
      ),
    );

    expect(find.text('Before bed'), findsOneWidget);
    expect(find.text('With breakfast'), findsNothing);
    expect(find.text('Morning, before food'), findsNothing);
  });

  testWidgets('never presents a clock time', (tester) async {
    // The resolver's anchor hours decide bucket spacing only. Showing them
    // would read as dosing advice the pipeline never authored.
    await _pump(
      tester,
      _plan(
        items: {
          DailySlot.morningEmpty: ['iron'],
          DailySlot.withDinner: ['calcium'],
          DailySlot.bedtime: ['magnesium'],
        },
      ),
    );

    for (final banned in const ['7:00', '8:00', '18:00', '22:00', 'am', 'pm']) {
      expect(
        find.textContaining(banned),
        findsNothing,
        reason: 'plan must not imply a clock time ($banned)',
      );
    }
  });

  testWidgets('surfaces an unplaceable constraint verbatim', (tester) async {
    const authored = 'Take these at least 20 hours apart.';
    await _pump(
      tester,
      _plan(
        items: {
          DailySlot.withBreakfast: ['iron'],
        },
        unsatisfied: const [
          UnsatisfiedTimingConstraint(
            ruleId: 'r1',
            advice: authored,
            reason: 'Needs more separation than one day allows.',
          ),
        ],
      ),
    );

    expect(find.text(authored), findsOneWidget);
    expect(find.text('Timing to review'), findsOneWidget);
  });

  testWidgets('conflict copy stays calm-advisory', (tester) async {
    await _pump(
      tester,
      _plan(
        unsatisfied: const [
          UnsatisfiedTimingConstraint(
            ruleId: 'r1',
            advice: 'Separate these by four hours.',
            reason: 'Needs more separation than one day allows.',
          ),
        ],
      ),
    );

    for (final banned in const [
      'Stop',
      'Avoid',
      'Do not',
      "Don't",
      'WARNING',
      'ERROR',
      'failed',
      'impossible',
    ]) {
      expect(
        find.textContaining(banned),
        findsNothing,
        reason: 'conflict copy must stay calm-advisory ($banned)',
      );
    }
    expect(find.textContaining('worth a conversation'), findsOneWidget);
  });

  testWidgets('renders conflicts even when nothing could be placed', (
    tester,
  ) async {
    await _pump(
      tester,
      _plan(
        unsatisfied: const [
          UnsatisfiedTimingConstraint(
            ruleId: 'r1',
            advice: 'Conflicting guidance for iron.',
            reason: 'Both with-food and without-food timing.',
          ),
        ],
      ),
    );

    expect(find.text('Conflicting guidance for iron.'), findsOneWidget);
  });
}
