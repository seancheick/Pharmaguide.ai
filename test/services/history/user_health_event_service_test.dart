import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:pharmaguide/services/history/user_health_event_service.dart';

void main() {
  late UserDatabase database;
  late HealthEventRepository history;
  late UserHealthEventService service;

  setUp(() {
    database = UserDatabase.memory();
    history = HealthEventRepository(database);
    service = UserHealthEventService(
      history,
      subjectIdFactory: () => 'subject-1',
    );
  });

  tearDown(() => database.close());

  test('creates an exam and follow-up reminder atomically', () async {
    final examAt = DateTime.utc(2026, 8, 2, 10);
    final followUpAt = DateTime.utc(2026, 8, 9, 9);

    final id = await service.create(
      UserHealthEventInput(
        kind: UserHealthEventKind.examOrTest,
        title: 'Bone density scan',
        date: examAt,
        status: UserHealthEventStatus.scheduled,
        note: 'Bring the referral.',
        followUpAt: followUpAt,
        reminderAt: examAt.subtract(const Duration(days: 1)),
        attachments: const [
          LocalHealthAttachment(
            path: '/local/referral.pdf',
            displayName: 'Referral.pdf',
            mimeType: 'application/pdf',
          ),
        ],
      ),
    );

    expect(id, 'subject-1');
    final events = await history.getTimeline();
    expect(events, hasLength(2));
    expect(
      events.map((event) => event.eventType),
      containsAll([
        HealthEventTypes.examScheduled,
        HealthEventTypes.reminderScheduled,
      ]),
    );
    final exam = events.singleWhere(
      (event) => event.eventType == HealthEventTypes.examScheduled,
    );
    final metadata = jsonDecode(exam.metadataJson!) as Map<String, dynamic>;
    expect(metadata['attachments'], hasLength(1));
    expect(exam.reminderAt?.toUtc(), examAt.subtract(const Duration(days: 1)));
    final followUp = events.singleWhere(
      (event) => event.eventType == HealthEventTypes.reminderScheduled,
    );
    expect(followUp.effectiveAt.toUtc(), followUpAt);
    expect(followUp.reminderAt?.toUtc(), followUpAt);
  });

  test('reschedule appends a new state instead of editing history', () async {
    await service.create(
      UserHealthEventInput(
        kind: UserHealthEventKind.doctorVisit,
        title: 'Primary care',
        date: DateTime.utc(2026, 8, 2),
        status: UserHealthEventStatus.scheduled,
      ),
    );
    await service.reschedule(
      kind: UserHealthEventKind.doctorVisit,
      subjectId: 'subject-1',
      title: 'Primary care',
      newDate: DateTime.utc(2026, 8, 5),
    );

    final events = await history.getTimeline();
    expect(events, hasLength(2));
    expect(
      events.map((event) => event.eventType),
      contains(HealthEventTypes.appointmentRescheduled),
    );
  });

  test('rejects a blank event title', () {
    expect(
      () => service.create(
        UserHealthEventInput(
          kind: UserHealthEventKind.personalNote,
          title: ' ',
          date: DateTime.utc(2026, 8, 2),
        ),
      ),
      throwsFormatException,
    );
  });
}
