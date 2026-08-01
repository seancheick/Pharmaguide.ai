// Accessibility contract for the surfaces added in the longitudinal work.
//
// Two rules drive these: information must never be carried by an icon or a
// colour alone, and text must survive large accessibility type sizes without
// clipping the value it is reporting.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_daily_plan_card.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_depletion_card.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/depletion_watch.dart';
import 'package:pharmaguide/services/stack/timing_sequence_resolver.dart';

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
  group('daily plan accessibility', () {
    testWidgets('each slot is announced as one labelled group', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PGDailyPlanCard(
            plan: _plan(
              items: {
                DailySlot.withBreakfast: ['iron', 'vitamin c'],
              },
            ),
          ),
        ),
      );

      // Commas, not middots: punctuation is visual, not something to read out.
      expect(
        find.bySemanticsLabel('With breakfast: iron, vitamin c'),
        findsOneWidget,
      );
    });

    testWidgets('section titles are exposed as headings', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          PGDailyPlanCard(
            plan: _plan(
              items: {
                DailySlot.bedtime: ['magnesium'],
              },
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.text('One way to space your day')),
        matchesSemantics(label: 'One way to space your day', isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('survives a large accessibility text size', (tester) async {
      // Dynamic Type at 2x is a supported setting, not an edge case.
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          PGDailyPlanCard(
            plan: _plan(
              items: {
                DailySlot.morningEmpty: ['iron'],
                DailySlot.withDinner: ['calcium', 'magnesium glycinate'],
              },
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
        find.bySemanticsLabel('Tracked here for about 3 years'),
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
