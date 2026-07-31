// Tests for DepletionWatchResolver (roadmap Phase 1).
//
// The resolver does date arithmetic over reviewer-authored thresholds. It must
// never invent a threshold, never fire for an entry a reviewer did not author,
// and never report a negative span.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/depletion_watch.dart';

const _metforminRxcui = '860974';
const _ppiClassId = 'class:acid_suppressants';

Map<String, dynamic> _data({
  Object? metforminThreshold,
  Object? metforminBasis,
  Object? ppiThreshold,
  Object? ppiBasis,
}) {
  return {
    'depletions': [
      {
        'id': 'DEP_METFORMIN_VITAMINB12',
        'drug_ref': {'id': _metforminRxcui, 'display_name': 'Metformin'},
        'depleted_nutrient': {
          'standard_name': 'Vitamin B12',
          'canonical_id': 'vitamin_b12',
        },
        'depletion_type': 'depletion',
        'severity': 'significant',
        'citation_review_status': 'verified',
        'mechanism': 'Impairs B12 absorption.',
        'recommendation': 'Worth a conversation with your clinician.',
        'evidence_level': 'established',
        if (metforminThreshold != null) ...{
          'watch_threshold_days': metforminThreshold,
          'watch_review_status': 'approved',
          'watch_approver': 'PharmaGuide Clinical Team',
        },
        if (metforminBasis != null) 'watch_basis': metforminBasis,
      },
      {
        'id': 'DEP_ANTACIDS_IRON',
        'drug_ref': {'id': _ppiClassId, 'display_name': 'Acid reducers'},
        'depleted_nutrient': {'standard_name': 'Iron', 'canonical_id': 'iron'},
        'depletion_type': 'depletion',
        'severity': 'moderate',
        'citation_review_status': 'verified',
        'mechanism': 'Acid suppression lowers non-heme iron absorption.',
        'recommendation': 'Worth a conversation with your clinician.',
        'evidence_level': 'established',
        if (ppiThreshold != null) ...{
          'watch_threshold_days': ppiThreshold,
          'watch_review_status': 'approved',
          'watch_approver': 'PharmaGuide Clinical Team',
        },
        if (ppiBasis != null) 'watch_basis': ppiBasis,
      },
    ],
  };
}

WatchedMedication _metformin(String entryId) => (
  stackEntryId: entryId,
  identity: const DepletionMedicationIdentity(
    name: 'Metformin',
    rxcui: _metforminRxcui,
  ),
);

WatchedMedication _ppi(String entryId, String name) => (
  stackEntryId: entryId,
  identity: DepletionMedicationIdentity(
    name: name,
    drugClassIds: const [_ppiClassId],
  ),
);

void main() {
  final resolver = DepletionWatchResolver();
  final now = DateTime.utc(2026, 7, 30);

  test('an authored threshold that has elapsed is due', () {
    final statuses = resolver.evaluate(
      medications: [_metformin('entry-1')],
      depletionsData: _data(
        metforminThreshold: 730,
        metforminBasis: 'Reviewer basis.',
      ),
      trackedSinceByStackEntry: {'entry-1': DateTime.utc(2023, 1, 1)},
      now: now,
    );

    final status = statuses['DEP_METFORMIN_VITAMINB12'];
    expect(status, isNotNull);
    expect(status!.isDue, isTrue);
    expect(status.thresholdDays, 730);
    expect(status.basis, 'Reviewer basis.');
    expect(status.trackedMonths, greaterThan(40));
  });

  test('an authored threshold not yet elapsed is not due', () {
    final statuses = resolver.evaluate(
      medications: [_metformin('entry-1')],
      depletionsData: _data(
        metforminThreshold: 730,
        metforminBasis: 'Reviewer basis.',
      ),
      trackedSinceByStackEntry: {'entry-1': DateTime.utc(2026, 6, 1)},
      now: now,
    );

    expect(statuses['DEP_METFORMIN_VITAMINB12']!.isDue, isFalse);
  });

  test('an entry with no authored threshold produces no status', () {
    // This is every entry today. The feature stays inert until curated data
    // enables it.
    final statuses = resolver.evaluate(
      medications: [_metformin('entry-1')],
      depletionsData: _data(),
      trackedSinceByStackEntry: {'entry-1': DateTime.utc(2015, 1, 1)},
      now: now,
    );

    expect(statuses, isEmpty);
  });

  test('a threshold without a basis produces no status', () {
    final statuses = resolver.evaluate(
      medications: [_metformin('entry-1')],
      depletionsData: _data(metforminThreshold: 730),
      trackedSinceByStackEntry: {'entry-1': DateTime.utc(2015, 1, 1)},
      now: now,
    );

    expect(statuses, isEmpty);
  });

  test('a medication with no tracking start is skipped', () {
    // Pre-v10 rows with no event-log history and no added_at fallback.
    final statuses = resolver.evaluate(
      medications: [_metformin('entry-1')],
      depletionsData: _data(
        metforminThreshold: 730,
        metforminBasis: 'Reviewer basis.',
      ),
      trackedSinceByStackEntry: const {},
      now: now,
    );

    expect(statuses, isEmpty);
  });

  test('a backwards device clock reads as zero, never negative', () {
    final statuses = resolver.evaluate(
      medications: [_metformin('entry-1')],
      depletionsData: _data(
        metforminThreshold: 730,
        metforminBasis: 'Reviewer basis.',
      ),
      trackedSinceByStackEntry: {'entry-1': DateTime.utc(2027, 1, 1)},
      now: now,
    );

    final status = statuses['DEP_METFORMIN_VITAMINB12']!;
    expect(status.trackedFor, Duration.zero);
    expect(status.trackedFor.isNegative, isFalse);
    expect(status.isDue, isFalse);
  });

  test('two drugs driving one relationship use the longer exposure', () {
    // Same class, different rows: the exposure is as old as the longer-standing
    // medication, so the earliest start wins.
    final statuses = resolver.evaluate(
      medications: [
        _ppi('entry-1', 'Omeprazole'),
        _ppi('entry-2', 'Famotidine'),
      ],
      depletionsData: _data(ppiThreshold: 730, ppiBasis: 'Reviewer basis.'),
      trackedSinceByStackEntry: {
        'entry-1': DateTime.utc(2019, 1, 1),
        'entry-2': DateTime.utc(2026, 7, 1),
      },
      now: now,
    );

    final status = statuses['DEP_ANTACIDS_IRON']!;
    expect(status.isDue, isTrue);
    expect(status.trackedFor.inDays, greaterThan(2700));
  });

  test('only the entry whose threshold is authored is watched', () {
    final statuses = resolver.evaluate(
      medications: [_metformin('entry-1'), _ppi('entry-2', 'Omeprazole')],
      depletionsData: _data(ppiThreshold: 730, ppiBasis: 'Reviewer basis.'),
      trackedSinceByStackEntry: {
        'entry-1': DateTime.utc(2015, 1, 1),
        'entry-2': DateTime.utc(2015, 1, 1),
      },
      now: now,
    );

    expect(statuses.keys, ['DEP_ANTACIDS_IRON']);
  });

  test('a local-time tracking start is compared correctly', () {
    // getStackTrackedSince normalizes to UTC, but a fallback added_at from the
    // stack row arrives in local time. Both must yield the same verdict.
    final statuses = resolver.evaluate(
      medications: [_metformin('entry-1')],
      depletionsData: _data(
        metforminThreshold: 730,
        metforminBasis: 'Reviewer basis.',
      ),
      trackedSinceByStackEntry: {'entry-1': DateTime(2023, 1, 1)},
      now: now,
    );

    expect(statuses['DEP_METFORMIN_VITAMINB12']!.isDue, isTrue);
  });
}
