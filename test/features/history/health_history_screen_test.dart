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

  testWidgets('shows unified events without duplicating scan history', (
    tester,
  ) async {
    await database.recordScanEvent(
      dsldId: 'scan-only',
      productName: 'Scanned Product',
    );
    await history.append(
      HealthEventDraft(
        eventType: HealthEventTypes.noteAdded,
        source: HealthEventSource.user,
        subjectType: 'note',
        title: 'Felt better after breakfast',
        effectiveAt: DateTime.now(),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Felt better after breakfast'), findsOneWidget);
    expect(find.text('Scanned Product'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('explains why a resolved signal changed', (tester) async {
    await history.append(
      HealthEventDraft(
        eventType: HealthEventTypes.clinicalSignalResolved,
        source: HealthEventSource.clinicalSignal,
        subjectType: 'clinical_signal',
        subjectId: 'signal-1',
        state: HealthEventState.resolved,
        title: 'Resolved: Vitamin K consistency',
        effectiveAt: DateTime.now(),
        metadata: const {
          'resolution_reason': 'no_longer_present_after_complete_analysis',
        },
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolved: Vitamin K consistency'));
    await tester.pumpAndSettle();

    expect(find.text('Why this changed'), findsOneWidget);
    expect(
      find.textContaining('complete recheck no longer found'),
      findsOneWidget,
    );
    await _unmount(tester);
  });

  testWidgets('Upcoming projects scheduled care from the same log', (
    tester,
  ) async {
    await history.append(
      HealthEventDraft(
        eventType: HealthEventTypes.appointmentScheduled,
        source: HealthEventSource.user,
        subjectType: 'appointment',
        subjectId: 'appointment-1',
        state: HealthEventState.scheduled,
        title: 'Primary care appointment',
        effectiveAt: DateTime.now().add(const Duration(days: 3)),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();

    expect(find.text('Primary care appointment'), findsOneWidget);
    await tester.tap(find.text('Primary care appointment'));
    await tester.pumpAndSettle();
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Reschedule'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();
    // Completing a doctor visit now offers an optional note first (visit loop,
    // Phase 2). Skipping is the default path and still completes the visit.
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(
      (await history.getTimeline()).map((event) => event.eventType),
      contains(HealthEventTypes.appointmentCompleted),
    );
    await _unmount(tester);
  });

  testWidgets('records viewed and acknowledged clinical-signal state', (
    tester,
  ) async {
    await history.append(
      HealthEventDraft(
        eventType: HealthEventTypes.clinicalSignalAdded,
        source: HealthEventSource.clinicalSignal,
        subjectType: 'clinical_signal',
        subjectId: 'signal-active',
        title: 'New: Vitamin K consistency',
        effectiveAt: DateTime.now(),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New: Vitamin K consistency'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as reviewed'), findsOneWidget);
    await tester.tap(find.text('Mark as reviewed'));
    await tester.pumpAndSettle();

    final events = await history.getTimeline();
    expect(
      events.map((event) => event.eventType),
      containsAll([
        HealthEventTypes.clinicalSignalViewed,
        HealthEventTypes.clinicalSignalAcknowledged,
      ]),
    );
    await _unmount(tester);
  });

  testWidgets('shows structured fields for a changed clinical signal', (
    tester,
  ) async {
    await history.append(
      HealthEventDraft(
        eventType: HealthEventTypes.clinicalSignalChanged,
        source: HealthEventSource.clinicalSignal,
        subjectType: 'clinical_signal',
        subjectId: 'signal-changed',
        title: 'Changed: Supplement timing',
        effectiveAt: DateTime.now(),
        previousValue: const {
          'clinical_severity': 'monitor',
          'body': 'Original explanation',
        },
        currentValue: const {
          'clinical_severity': 'caution',
          'body': 'Updated explanation',
        },
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Changed: Supplement timing'));
    await tester.pumpAndSettle();

    expect(find.text('Changed fields'), findsOneWidget);
    expect(find.text('Clinical severity'), findsOneWidget);
    expect(find.text('Explanation'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('add action opens the bounded event form', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add health event'));
    await tester.pumpAndSettle();

    expect(find.text('Add health event'), findsOneWidget);
    expect(find.text('Doctor visit'), findsOneWidget);
    expect(find.text('Save event'), findsOneWidget);
    expect(find.textContaining('Lab values'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('shows an event attachment from the canonical metadata', (
    tester,
  ) async {
    await history.append(
      HealthEventDraft(
        eventType: HealthEventTypes.examCompleted,
        source: HealthEventSource.user,
        subjectType: 'exam',
        subjectId: 'exam-with-photo',
        title: 'Eye exam',
        effectiveAt: DateTime.now(),
        metadata: const {
          'attachments': [
            {
              'path': '/private/health-history/eye-exam.jpg',
              'display_name': 'eye-exam.jpg',
              'mime_type': 'image/jpeg',
            },
          ],
        },
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eye exam'));
    await tester.pumpAndSettle();

    expect(find.text('Attachments'), findsOneWidget);
    expect(find.text('eye-exam.jpg'), findsOneWidget);
    expect(find.text('Private on-device photo'), findsOneWidget);
    await _unmount(tester);
  });
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Drift closes watched queries on a zero-duration timer. Advance fake time
  // once after ProviderScope disposal so the stream store can finish cleanup.
  await tester.pump(const Duration(milliseconds: 1));
}
