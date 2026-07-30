// The user-reported start date must take precedence over when the row entered
// this device.
//
// This is the whole reason the field exists: someone on metformin since 2019
// who installed the app last week reads as "tracked 6 days" from `added_at`
// and never reaches a multi-year watch threshold. Reporting the real start
// date is what makes duration-aware monitoring true for the people it was
// built for.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/depletion_watch.dart';

const _rxcui = '860974';

Map<String, dynamic> get _data => {
  'depletions': [
    {
      'id': 'DEP_METFORMIN_VITAMINB12',
      'drug_ref': {'id': _rxcui, 'display_name': 'Metformin'},
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
      'watch_threshold_days': 1460,
      'watch_basis': 'Reviewer basis.',
      'watch_review_status': 'approved',
    },
  ],
};

/// Mirrors the precedence in `depletionWatchProvider`: reported start date,
/// then the event log, then `added_at`.
Future<Map<String, DateTime>> resolveTrackedSince(
  UserDatabase database,
  HealthEventRepository history,
) async {
  final logged = await history.getStackTrackedSince();
  final rows = await database.getActiveStack();
  final out = <String, DateTime>{};
  for (final row in rows) {
    if (row.type != 'medication') continue;
    final reported = row.startedAt;
    out[row.id] = (reported ?? logged[row.id] ?? row.addedAt).toUtc();
  }
  return out;
}

void main() {
  late UserDatabase database;
  late HealthEventRepository history;
  final resolver = DepletionWatchResolver();
  final now = DateTime.utc(2026, 7, 30);

  setUp(() {
    database = UserDatabase.memory();
    history = HealthEventRepository(database);
  });

  tearDown(() => database.close());

  Future<void> addMetformin({DateTime? startedAt, DateTime? addedAt}) async {
    await database
        .into(database.userStacksLocal)
        .insert(
          UserStacksLocalCompanion.insert(
            id: 'entry-1',
            name: 'Metformin',
            type: const Value('medication'),
            rxcui: const Value(_rxcui),
            startedAt: Value(startedAt),
            addedAt: addedAt == null ? const Value.absent() : Value(addedAt),
          ),
        );
  }

  Future<Map<String, DepletionWatchStatus>> evaluate() async {
    return resolver.evaluate(
      medications: [
        (
          stackEntryId: 'entry-1',
          identity: const DepletionMedicationIdentity(
            name: 'Metformin',
            rxcui: _rxcui,
          ),
        ),
      ],
      depletionsData: _data,
      trackedSinceByStackEntry: await resolveTrackedSince(database, history),
      now: now,
    );
  }

  test('without a start date, a recent install never reaches a 4-year '
      'threshold', () async {
    await addMetformin(addedAt: DateTime.utc(2026, 7, 24));

    final statuses = await evaluate();
    expect(statuses['DEP_METFORMIN_VITAMINB12']!.isDue, isFalse);
  });

  test('reporting the real start date makes the watch due', () async {
    // Same row, same install date — the person simply told the app the truth.
    await addMetformin(
      startedAt: DateTime.utc(2019, 5, 1),
      addedAt: DateTime.utc(2026, 7, 24),
    );

    final status = (await evaluate())['DEP_METFORMIN_VITAMINB12']!;
    expect(status.isDue, isTrue);
    expect(status.trackedFor.inDays, greaterThan(2600));
  });

  test('the reported date beats the event log', () async {
    await addMetformin(
      startedAt: DateTime.utc(2019, 5, 1),
      addedAt: DateTime.utc(2026, 7, 24),
    );
    await history.append(
      HealthEventDraft(
        eventType: HealthEventTypes.stackItemAdded,
        source: HealthEventSource.stack,
        subjectType: 'medication',
        subjectId: 'entry-1',
        title: 'Started Metformin',
        effectiveAt: DateTime.utc(2026, 7, 24),
      ),
    );

    final status = (await evaluate())['DEP_METFORMIN_VITAMINB12']!;
    expect(status.isDue, isTrue);
  });

  test('clearing the start date falls back to the log', () async {
    await addMetformin(addedAt: DateTime.utc(2026, 7, 24));
    await history.append(
      HealthEventDraft(
        eventType: HealthEventTypes.stackItemAdded,
        source: HealthEventSource.stack,
        subjectType: 'medication',
        subjectId: 'entry-1',
        title: 'Started Metformin',
        effectiveAt: DateTime.utc(2021, 1, 1),
      ),
    );

    final status = (await evaluate())['DEP_METFORMIN_VITAMINB12']!;
    expect(status.isDue, isTrue);
    expect(status.trackedFor.inDays, greaterThan(1800));
  });

  test('a start date cannot produce a negative span', () async {
    await addMetformin(startedAt: DateTime.utc(2030, 1, 1));

    final status = (await evaluate())['DEP_METFORMIN_VITAMINB12']!;
    expect(status.trackedFor, Duration.zero);
    expect(status.isDue, isFalse);
  });
}
