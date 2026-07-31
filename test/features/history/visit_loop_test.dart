// Widget tests for the Phase 2 visit loop.
//
// The loop connects two things that already existed and never met: the
// appointment lifecycle and the clinician report. Two invariants matter most —
// the report offer appears only for a doctor visit, and the post-visit capture
// is never able to block completing the visit.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/health_event_repository.dart';
import 'package:pharmaguide/features/history/health_history_screen.dart';

void main() {
  late UserDatabase database;
  late HealthEventRepository history;

  setUp(() {
    database = UserDatabase.memory();
    history = HealthEventRepository(database);
  });

  tearDown(() => database.close());

  Widget app() {
    return ProviderScope(
      overrides: [userDatabaseProvider.overrideWithValue(database)],
      child: const MaterialApp(home: HealthHistoryScreen()),
    );
  }

  Future<void> scheduleCare({
    required String eventType,
    required String subjectType,
    required String subjectId,
    required String title,
  }) {
    return history.append(
      HealthEventDraft(
        eventType: eventType,
        source: HealthEventSource.user,
        subjectType: subjectType,
        subjectId: subjectId,
        state: HealthEventState.scheduled,
        title: title,
        effectiveAt: DateTime.now().add(const Duration(days: 5)),
      ),
    );
  }

  Future<void> openUpcomingDetail(WidgetTester tester, String title) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // Switch to the Upcoming segment, where scheduled care lives.
    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  /// Drift closes watched queries on a zero-duration timer. Without unmounting
  /// and advancing fake time once, the stream subscription outlives the test
  /// and the run hangs at teardown.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('an upcoming doctor visit offers the stack report', (
    tester,
  ) async {
    await scheduleCare(
      eventType: HealthEventTypes.appointmentScheduled,
      subjectType: 'appointment',
      subjectId: 'appt-1',
      title: 'Cardiology follow-up',
    );

    await openUpcomingDetail(tester, 'Cardiology follow-up');

    expect(find.text('Bring your stack'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a scheduled exam does not offer the stack report', (
    tester,
  ) async {
    // The report is a conversation aid for a clinician visit. A lab draw or a
    // procedure reminder is not that conversation.
    await scheduleCare(
      eventType: HealthEventTypes.examScheduled,
      subjectType: 'exam',
      subjectId: 'exam-1',
      title: 'Fasting blood panel',
    );

    await openUpcomingDetail(tester, 'Fasting blood panel');

    expect(find.text('Bring your stack'), findsNothing);
    expect(find.text('Complete'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('completing a visit offers an optional note', (tester) async {
    await scheduleCare(
      eventType: HealthEventTypes.appointmentScheduled,
      subjectType: 'appointment',
      subjectId: 'appt-1',
      title: 'Cardiology follow-up',
    );

    await openUpcomingDetail(tester, 'Cardiology follow-up');
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();

    expect(find.text('Anything change?'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('skipping the note still completes the visit', (tester) async {
    await scheduleCare(
      eventType: HealthEventTypes.appointmentScheduled,
      subjectType: 'appointment',
      subjectId: 'appt-1',
      title: 'Cardiology follow-up',
    );

    await openUpcomingDetail(tester, 'Cardiology follow-up');
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    final events = await history.getTimeline();
    final completed = events.where(
      (e) => e.eventType == HealthEventTypes.appointmentCompleted,
    );
    expect(completed, hasLength(1));
    expect(completed.single.summary, isNull);
    await unmount(tester);
  });

  testWidgets('a saved note is recorded on the completion event', (
    tester,
  ) async {
    await scheduleCare(
      eventType: HealthEventTypes.appointmentScheduled,
      subjectType: 'appointment',
      subjectId: 'appt-1',
      title: 'Cardiology follow-up',
    );

    await openUpcomingDetail(tester, 'Cardiology follow-up');
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Started a new statin.');
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();

    final events = await history.getTimeline();
    final completed = events.firstWhere(
      (e) => e.eventType == HealthEventTypes.appointmentCompleted,
    );
    expect(completed.summary, 'Started a new statin.');
    await unmount(tester);
  });

  testWidgets('completing a non-visit never asks for a note', (tester) async {
    await scheduleCare(
      eventType: HealthEventTypes.examScheduled,
      subjectType: 'exam',
      subjectId: 'exam-1',
      title: 'Fasting blood panel',
    );

    await openUpcomingDetail(tester, 'Fasting blood panel');
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();

    expect(find.text('Anything change?'), findsNothing);
    final events = await history.getTimeline();
    expect(
      events.where((e) => e.eventType == HealthEventTypes.examCompleted),
      hasLength(1),
    );
    await unmount(tester);
  });
}
