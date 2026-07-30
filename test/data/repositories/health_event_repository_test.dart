import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';

void main() {
  late UserDatabase database;
  late HealthEventRepository repository;
  var nextId = 0;
  final recordedAt = DateTime.utc(2026, 7, 30, 12);

  setUp(() {
    database = UserDatabase.memory();
    repository = HealthEventRepository(
      database,
      idFactory: () => 'event-${nextId++}',
      clock: () => recordedAt.add(Duration(minutes: nextId)),
    );
  });

  tearDown(() => database.close());

  test(
    'appends structured before/after values without rewriting history',
    () async {
      final happenedAt = DateTime.utc(2026, 7, 29, 9);

      await repository.append(
        HealthEventDraft(
          eventType: HealthEventTypes.stackItemChanged,
          source: HealthEventSource.stack,
          subjectType: 'supplement',
          subjectId: 'stack-1',
          title: 'Changed Magnesium',
          effectiveAt: happenedAt,
          previousValue: const {'dosage': '1 capsule'},
          currentValue: const {'dosage': '2 capsules'},
        ),
      );

      final events = await repository.getTimeline();
      expect(events, hasLength(1));
      expect(events.single.effectiveAt.toUtc(), happenedAt);
      expect(jsonDecode(events.single.previousValueJson!), {
        'dosage': '1 capsule',
      });
      expect(jsonDecode(events.single.currentValueJson!), {
        'dosage': '2 capsules',
      });
    },
  );

  test('dedupe key makes system observations idempotent', () async {
    final draft = HealthEventDraft(
      eventType: HealthEventTypes.clinicalSignalAdded,
      source: HealthEventSource.clinicalSignal,
      subjectType: 'clinical_signal',
      subjectId: 'warfarin-vitamin-k',
      title: 'Vitamin K consistency signal added',
      effectiveAt: recordedAt,
      dedupeKey: 'signal:warfarin-vitamin-k:hash-1',
    );

    expect(await repository.append(draft), isTrue);
    expect(await repository.append(draft), isFalse);
    expect(await repository.getTimeline(), hasLength(1));
  });

  test('upcoming projection uses latest state for a subject', () async {
    final appointmentAt = DateTime.utc(2026, 8, 4, 14);
    await repository.append(
      HealthEventDraft(
        eventType: HealthEventTypes.appointmentScheduled,
        source: HealthEventSource.user,
        subjectType: 'appointment',
        subjectId: 'appointment-1',
        state: HealthEventState.scheduled,
        title: 'Primary care appointment',
        effectiveAt: appointmentAt,
      ),
    );

    final first = await repository.watchUpcoming(now: recordedAt).first;
    expect(first.map((event) => event.subjectId), ['appointment-1']);

    await repository.append(
      HealthEventDraft(
        eventType: HealthEventTypes.appointmentCancelled,
        source: HealthEventSource.user,
        subjectType: 'appointment',
        subjectId: 'appointment-1',
        state: HealthEventState.cancelled,
        title: 'Primary care appointment cancelled',
        effectiveAt: appointmentAt,
      ),
    );

    final second = await repository.watchUpcoming(now: recordedAt).first;
    expect(second, isEmpty);
    expect(await repository.getTimeline(), hasLength(2));
  });

  test('database sequence resolves same-timestamp state transitions', () async {
    var id = 0;
    final sameTimestampRepository = HealthEventRepository(
      database,
      idFactory: () => 'same-time-${id++}',
      clock: () => recordedAt,
    );
    final appointmentAt = DateTime.utc(2026, 8, 4, 14);
    await sameTimestampRepository.append(
      HealthEventDraft(
        eventType: HealthEventTypes.appointmentScheduled,
        source: HealthEventSource.user,
        subjectType: 'appointment',
        subjectId: 'same-time-appointment',
        state: HealthEventState.scheduled,
        title: 'Scheduled appointment',
        effectiveAt: appointmentAt,
      ),
    );
    await sameTimestampRepository.append(
      HealthEventDraft(
        eventType: HealthEventTypes.appointmentCancelled,
        source: HealthEventSource.user,
        subjectType: 'appointment',
        subjectId: 'same-time-appointment',
        state: HealthEventState.cancelled,
        title: 'Cancelled appointment',
        effectiveAt: appointmentAt,
      ),
    );

    expect(
      await sameTimestampRepository.watchUpcoming(now: recordedAt).first,
      isEmpty,
    );
  });

  test('persists stable snake-case source identifiers', () async {
    await repository.append(
      HealthEventDraft(
        eventType: HealthEventTypes.clinicalSignalAdded,
        source: HealthEventSource.clinicalSignal,
        subjectType: 'clinical_signal',
        title: 'Clinical signal',
        effectiveAt: recordedAt,
      ),
    );

    expect((await repository.getTimeline()).single.source, 'clinical_signal');
  });

  test('rejects blank event contracts', () async {
    expect(
      () => repository.append(
        HealthEventDraft(
          eventType: '',
          source: HealthEventSource.user,
          subjectType: 'note',
          title: 'Note',
          effectiveAt: recordedAt,
        ),
      ),
      throwsFormatException,
    );
  });
}
