// Widget tests for the Phase 1 watch annotation on PGDepletionCard.
//
// The card must be byte-identical to its pre-watch self whenever no reviewer
// authored a threshold — that is every entry today — and must never claim the
// person has *taken* a medication for a duration. It only knows how long the
// medication has been tracked on this device.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/stack/v2/widgets/pg_depletion_card.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/depletion_watch.dart';

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

DepletionWatchStatus _status({required Duration trackedFor}) {
  return DepletionWatchStatus(
    depletionId: 'DEP_METFORMIN_VITAMINB12',
    thresholdDays: 730,
    basis: 'Reviewer basis.',
    trackedFor: trackedFor,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  Map<String, DepletionWatchStatus> watchStatuses = const {},
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PGDepletionCard(
            depletions: const [_match],
            watchStatuses: watchStatuses,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders no duration line when no threshold is authored', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('Tracked here'), findsNothing);
    // Detailed monitoring guidance belongs to the focused sheet, not the
    // concise summary row.
    expect(find.text('What to monitor'), findsOneWidget);
    expect(
      find.text('Consider discussing B12 testing at your next visit.'),
      findsNothing,
    );
  });

  testWidgets('renders no duration line before the threshold elapses', (
    tester,
  ) async {
    await _pump(
      tester,
      watchStatuses: {
        'DEP_METFORMIN_VITAMINB12': _status(
          trackedFor: const Duration(days: 200),
        ),
      },
    );

    expect(find.textContaining('Tracked here'), findsNothing);
  });

  testWidgets('renders the tracked duration once the threshold elapses', (
    tester,
  ) async {
    await _pump(
      tester,
      watchStatuses: {
        'DEP_METFORMIN_VITAMINB12': _status(
          trackedFor: const Duration(days: 1100),
        ),
      },
    );

    expect(
      find.textContaining('Tracked here for about 3 years'),
      findsOneWidget,
    );
  });

  testWidgets('renders months below two years', (tester) async {
    // Threshold shorter than two years, so the row is due while the elapsed
    // span still reads naturally in months.
    await _pump(
      tester,
      watchStatuses: {
        'DEP_METFORMIN_VITAMINB12': const DepletionWatchStatus(
          depletionId: 'DEP_METFORMIN_VITAMINB12',
          thresholdDays: 365,
          basis: 'Reviewer basis.',
          trackedFor: Duration(days: 400),
        ),
      },
    );

    expect(
      find.textContaining('Tracked here for about 13 months'),
      findsOneWidget,
    );
  });

  testWidgets('crosses from months to years at the two-year boundary', (
    tester,
  ) async {
    await _pump(
      tester,
      watchStatuses: {
        'DEP_METFORMIN_VITAMINB12': _status(
          trackedFor: const Duration(days: 750),
        ),
      },
    );

    expect(
      find.textContaining('Tracked here for about 2 years'),
      findsOneWidget,
    );
  });

  testWidgets('never claims the person has taken the medication', (
    tester,
  ) async {
    // added_at records when the row entered THIS device's stack. The
    // prescription may predate the app by years, so any "you have taken this
    // for N" phrasing would be a fabricated clinical claim.
    await _pump(
      tester,
      watchStatuses: {
        'DEP_METFORMIN_VITAMINB12': _status(
          trackedFor: const Duration(days: 1100),
        ),
      },
    );

    expect(find.textContaining('you have taken'), findsNothing);
    expect(find.textContaining("you've been taking"), findsNothing);
    expect(find.textContaining('You have been on'), findsNothing);
  });

  testWidgets('a status for a different entry does not annotate this row', (
    tester,
  ) async {
    await _pump(
      tester,
      watchStatuses: {
        'DEP_ANTACIDS_IRON': const DepletionWatchStatus(
          depletionId: 'DEP_ANTACIDS_IRON',
          thresholdDays: 730,
          basis: 'Reviewer basis.',
          trackedFor: Duration(days: 3000),
        ),
      },
    );

    expect(find.textContaining('Tracked here'), findsNothing);
  });

  testWidgets('watch copy stays calm-advisory', (tester) async {
    await _pump(
      tester,
      watchStatuses: {
        'DEP_METFORMIN_VITAMINB12': _status(
          trackedFor: const Duration(days: 1100),
        ),
      },
    );

    for (final banned in const [
      'Stop',
      'Avoid',
      'Do not',
      "Don't",
      'URGENT',
      'WARNING',
      'overdue',
      'Overdue',
    ]) {
      expect(
        find.textContaining(banned),
        findsNothing,
        reason: 'watch copy must stay calm-advisory ($banned)',
      );
    }
  });
}
