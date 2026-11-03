// A class bridge that fails must not read as a complete check. Runs the real
// identity, device-profile and match providers. Fixture ids are fictional.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert.dart';
import 'package:pharmaguide/services/safety_alerts/safety_alert_repository.dart';

const _rxcui = '0000001';

class _FakeRepository implements SafetyAlertRepository {
  @override
  Future<SafetyAlertRelease> loadCurrent() async => const SafetyAlertRelease(
    alerts: [],
    baselineRevisions: {},
    isComplete: true,
  );

  @override
  Future<List<SafetyAlert>> loadCachedAlerts() async => const [];
}

ProviderContainer _container({
  required List<UserStacksLocalData> stack,
  required List<Override> extra,
}) {
  final container = ProviderContainer(
    overrides: [
      activeStackProvider.overrideWith((ref) async => stack),
      safetyAlertRepositoryProvider.overrideWithValue(_FakeRepository()),
      evaluatorProfileFlagsProvider.overrideWith((ref) async => const {}),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

final _stack = [
  UserStacksLocalData(
    id: 'med-only-rxcui',
    type: 'medication',
    name: 'Fictional medication',
    rxcui: _rxcui,
    addedAt: DateTime.utc(2026, 11, 3),
    clientUpdatedAt: DateTime.utc(2026, 11, 3),
  ),
];

void main() {
  final readableProfile = loadedProfileProvider.overrideWith(
    (ref) async => const ProfileState(),
  );

  test(
    'no interaction DB at all: incomplete, and the RxCUI still matches',
    () async {
      final container = _container(stack: _stack, extra: [readableProfile]);

      final device = await container.read(deviceSafetyProfileProvider.future);
      final matches = await container.read(safetyAlertMatchesProvider.future);

      expect(device.medicationIds, contains(_rxcui));
      expect(device.isComplete, isFalse);
      expect(matches.isComplete, isFalse);
    },
  );

  test('the class table fails while the DB still opens: incomplete', () async {
    // The metadata read a Stack analysis checks still works here, so nothing
    // else on that path would notice.
    final db = InteractionDatabase.memory();
    addTearDown(db.close);
    await db.customStatement('DROP TABLE drug_class_map');
    final container = _container(
      stack: _stack,
      extra: [
        readableProfile,
        interactionDatabaseProvider.overrideWithValue(db),
      ],
    );

    final device = await container.read(deviceSafetyProfileProvider.future);
    final matches = await container.read(safetyAlertMatchesProvider.future);

    expect(device.medicationIds, contains(_rxcui));
    expect(device.isComplete, isFalse);
    expect(matches.isComplete, isFalse);
  });

  test(
    'a failed bridge reports fixed text, never the database error',
    () async {
      // SqliteException.toString writes the statement and its bound values.
      await CrashReportingService().initialize();
      CrashReportingService().clearBuffersForTest();
      final db = InteractionDatabase.memory();
      addTearDown(db.close);
      await db.customStatement('DROP TABLE drug_class_map');
      final container = _container(
        stack: _stack,
        extra: [
          readableProfile,
          interactionDatabaseProvider.overrideWithValue(db),
        ],
      );

      await container.read(deviceSafetyProfileProvider.future);

      final recorded = CrashReportingService().recordedErrors.singleWhere(
        (error) => error.hint == 'medication_identity:class_bridge_unavailable',
      );
      expect(
        recorded.summary,
        'Bad state: The medication class bridge could not be read.',
      );
    },
  );

  test('a failed profile read reports fixed text too', () async {
    await CrashReportingService().initialize();
    CrashReportingService().clearBuffersForTest();
    final db = InteractionDatabase.memory();
    addTearDown(db.close);
    final container = _container(
      stack: _stack,
      extra: [
        loadedProfileProvider.overrideWith(
          (ref) async => throw StateError('name: Testoprilex (fictional)'),
        ),
        interactionDatabaseProvider.overrideWithValue(db),
      ],
    );

    await container.read(deviceSafetyProfileProvider.future);

    final recorded = CrashReportingService().recordedErrors.singleWhere(
      (error) => error.hint == 'medication_identity:profile_unavailable',
    );
    expect(recorded.summary, isNot(contains('Testoprilex')));
  });

  test('a working bridge with nothing to find stays complete', () async {
    final db = InteractionDatabase.memory();
    addTearDown(db.close);
    final container = _container(
      stack: _stack,
      extra: [
        readableProfile,
        interactionDatabaseProvider.overrideWithValue(db),
      ],
    );

    expect(
      (await container.read(deviceSafetyProfileProvider.future)).isComplete,
      isTrue,
    );
  });

  test('no medications means the bridge never ran: still complete', () async {
    final container = _container(stack: const [], extra: [readableProfile]);

    expect(
      (await container.read(deviceSafetyProfileProvider.future)).isComplete,
      isTrue,
    );
  });

  test(
    'an unreadable profile is incomplete through the real identity read',
    () async {
      final db = InteractionDatabase.memory();
      addTearDown(db.close);
      final container = _container(
        stack: _stack,
        extra: [
          loadedProfileProvider.overrideWith(
            (ref) async => throw StateError('unreadable'),
          ),
          interactionDatabaseProvider.overrideWithValue(db),
        ],
      );

      final device = await container.read(deviceSafetyProfileProvider.future);

      expect(device.medicationIds, contains(_rxcui));
      expect(device.isComplete, isFalse);
    },
  );
}
