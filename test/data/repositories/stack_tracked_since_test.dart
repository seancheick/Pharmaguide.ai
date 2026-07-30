// Tests for HealthEventRepository.getStackTrackedSince() (roadmap Phase 1).
//
// "Continuously tracked since" is folded from the append-only log rather than
// read off the stack row, because the two differ in exactly the case that
// matters clinically: a medication that was stopped and later restarted has
// restarted its exposure, and its clock must restart with it.
//
// The distinction the fold encodes:
//   stack_item_restored = Undo of a removal (ActiveStackNotifier.restore
//     reverses a soft-delete on the same row id) -> CONTINUES the span.
//   stack_item_added after a removal = a genuine restart -> OPENS a new span.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';

void main() {
  late UserDatabase database;
  late HealthEventRepository repository;

  setUp(() {
    database = UserDatabase.memory();
    repository = HealthEventRepository(database);
  });

  tearDown(() => database.close());

  Future<void> emit(
    String eventType,
    String subjectId,
    DateTime at, {
    String subjectType = 'medication',
  }) {
    return repository.append(
      HealthEventDraft(
        eventType: eventType,
        source: HealthEventSource.stack,
        subjectType: subjectType,
        subjectId: subjectId,
        title: '$eventType $subjectId',
        effectiveAt: at,
      ),
    );
  }

  test('an added item is tracked from when it was added', () async {
    final addedAt = DateTime.utc(2025, 1, 10);
    await emit(HealthEventTypes.stackItemAdded, 'entry-1', addedAt);

    expect(await repository.getStackTrackedSince(), {'entry-1': addedAt});
  });

  test('a removed item is absent', () async {
    await emit(
      HealthEventTypes.stackItemAdded,
      'entry-1',
      DateTime.utc(2025, 1, 10),
    );
    await emit(
      HealthEventTypes.stackItemRemoved,
      'entry-1',
      DateTime.utc(2025, 6, 1),
    );

    expect(await repository.getStackTrackedSince(), isEmpty);
  });

  test('undo of a removal keeps the original span start', () async {
    // The snackbar Undo path. The user never actually stopped, so the clock
    // must not restart at the undo instant.
    final addedAt = DateTime.utc(2025, 1, 10);
    await emit(HealthEventTypes.stackItemAdded, 'entry-1', addedAt);
    await emit(
      HealthEventTypes.stackItemRemoved,
      'entry-1',
      DateTime.utc(2025, 6, 1),
    );
    await emit(
      HealthEventTypes.stackItemRestored,
      'entry-1',
      DateTime.utc(2025, 6, 1, 0, 0, 5),
    );

    expect(await repository.getStackTrackedSince(), {'entry-1': addedAt});
  });

  test('a genuine re-add restarts the span', () async {
    // Stopped in June, restarted in December: exposure restarted, so the
    // depletion clock must restart too.
    final restartedAt = DateTime.utc(2025, 12, 1);
    await emit(
      HealthEventTypes.stackItemAdded,
      'entry-1',
      DateTime.utc(2025, 1, 10),
    );
    await emit(
      HealthEventTypes.stackItemRemoved,
      'entry-1',
      DateTime.utc(2025, 6, 1),
    );
    await emit(HealthEventTypes.stackItemAdded, 'entry-1', restartedAt);

    expect(await repository.getStackTrackedSince(), {'entry-1': restartedAt});
  });

  test('subjects are folded independently', () async {
    final oneAddedAt = DateTime.utc(2025, 1, 10);
    final twoAddedAt = DateTime.utc(2025, 3, 4);
    await emit(HealthEventTypes.stackItemAdded, 'entry-1', oneAddedAt);
    await emit(HealthEventTypes.stackItemAdded, 'entry-2', twoAddedAt);
    await emit(
      HealthEventTypes.stackItemRemoved,
      'entry-2',
      DateTime.utc(2025, 5, 5),
    );
    await emit(HealthEventTypes.stackItemAdded, 'entry-3', twoAddedAt);

    expect(await repository.getStackTrackedSince(), {
      'entry-1': oneAddedAt,
      'entry-3': twoAddedAt,
    });
  });

  test('an empty log yields no tracked subjects', () async {
    // Stack items added before the v10 event log existed have no rows here.
    // They are absent rather than zero-length, so callers can fall back to the
    // stack row's own added_at instead of treating them as newly started.
    expect(await repository.getStackTrackedSince(), isEmpty);
  });

  test('non-stack events do not contribute', () async {
    await repository.append(
      HealthEventDraft(
        eventType: HealthEventTypes.appointmentScheduled,
        source: HealthEventSource.user,
        subjectType: 'appointment',
        subjectId: 'appt-1',
        state: HealthEventState.scheduled,
        title: 'Cardiology follow-up',
        effectiveAt: DateTime.utc(2025, 8, 1),
      ),
    );

    expect(await repository.getStackTrackedSince(), isEmpty);
  });

  test('a stack_item_changed row does not restart the span', () async {
    // Editing a dose is not a new exposure.
    final addedAt = DateTime.utc(2025, 1, 10);
    await emit(HealthEventTypes.stackItemAdded, 'entry-1', addedAt);
    await emit(
      HealthEventTypes.stackItemChanged,
      'entry-1',
      DateTime.utc(2025, 4, 2),
    );

    expect(await repository.getStackTrackedSince(), {'entry-1': addedAt});
  });
}
