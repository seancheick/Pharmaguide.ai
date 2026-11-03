import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/medication_identity_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';

UserStacksLocalData _medication({required String rxcui, String? classes}) {
  final ts = DateTime.utc(2026, 11, 3, 12);
  return UserStacksLocalData(
    id: 'med-$rxcui',
    type: 'medication',
    name: 'Fictional medication',
    rxcui: rxcui,
    drugClassesCol: classes,
    addedAt: ts,
    clientUpdatedAt: ts,
  );
}

Future<Set<String>> _identity(
  UserStacksLocalData row, {
  InteractionDatabase? db,
}) {
  final container = ProviderContainer(
    overrides: [
      activeStackProvider.overrideWith((ref) async => [row]),
      loadedProfileProvider.overrideWith(
        (ref) async => throw StateError('no profile in this test'),
      ),
      if (db != null) interactionDatabaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(container.dispose);
  return container.read(localMedicationIdentityProvider.future);
}

void main() {
  late InteractionDatabase db;

  setUp(() async {
    db = InteractionDatabase.memory();
    addTearDown(db.close);
    await db
        .into(db.drugClassMap)
        .insert(
          DrugClassMapCompanion.insert(
            classId: 'class:fake_members',
            className: 'Fictional members',
            drugRxcuisJson: '["0000002"]',
            excludedDrugRxcuisJson: const Value('["0000003"]'),
            source: 'fixture',
            lastUpdated: '2026-11-03',
          ),
        );
  });

  test('a brand row also answers to its offline ingredient RxCUI', () async {
    // Motrin. A rule written against ibuprofen has to reach it while offline,
    // before hydration has saved the generic on the row.
    expect(
      await _identity(_medication(rxcui: '202488'), db: db),
      containsAll(['202488', '5640']),
    );
  });

  test('a verified class member matches that class', () async {
    expect(
      await _identity(_medication(rxcui: '0000002'), db: db),
      contains('class:fake_members'),
    );
  });

  test('a saved class the data now excludes does not match', () async {
    expect(
      await _identity(
        _medication(rxcui: '0000003', classes: '["class:fake_members"]'),
        db: db,
      ),
      isNot(contains('class:fake_members')),
    );
  });

  test('saved classes still match when the bridge is unavailable', () async {
    // interactionDatabaseProvider is left throwing, as it is when the bundled
    // DB fails to open. An exclusion can't be read, and silence would be worse.
    expect(
      await _identity(
        _medication(rxcui: '0000003', classes: '["class:fake_members"]'),
      ),
      contains('class:fake_members'),
    );
  });
}
