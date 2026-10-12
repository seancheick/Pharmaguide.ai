import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';

UserStacksLocalData _row({
  required String id,
  required String type,
  String? drugClassesCol,
  String? rxcui,
  String? ingredientRxcuisCol,
}) {
  final ts = DateTime.utc(2026, 5, 4, 12);
  return UserStacksLocalData(
    id: id,
    type: type,
    name: id,
    dsldId: null,
    rxcui: rxcui,
    ingredientKeys: null,
    drugClassesCol: drugClassesCol,
    genericRxcui: null,
    ingredientRxcuisCol: ingredientRxcuisCol,
    dosage: null,
    frequency: null,
    addedAt: ts,
    clientUpdatedAt: ts,
    deletedAt: null,
    syncedAt: null,
  );
}

void main() {
  late InteractionDatabase database;
  setUp(() async {
    database = InteractionDatabase.memory();
    for (final row in [
      ['class:nsaids', '["5640"]', '["2473","4845"]'],
      ['class:antipsychotics', '["5093"]', '["6448"]'],
      ['class:oral_contraceptives', '["14584"]', '["6703"]'],
      ['class:lithium', '["6448"]', '[]'],
    ]) {
      await database.customStatement(
        'INSERT INTO drug_class_map (class_id, class_name, drug_rxcuis_json, excluded_drug_rxcuis_json, source, last_updated) VALUES (?, ?, ?, ?, ?, ?)',
        [row[0], row[0], row[1], row[2], 'fixture', '2026-10-12'],
      );
    }
  });
  tearDown(() => database.close());
  test(
    'unavailable class database stays an error, not an empty check',
    () async {
      await database.close();
      final container = ProviderContainer(
        overrides: [
          interactionDatabaseProvider.overrideWithValue(database),
          activeStackProvider.overrideWith(
            (ref) async => [
              _row(
                id: 'ibuprofen',
                type: 'medication',
                rxcui: '5640',
                drugClassesCol: '["class:nsaids"]',
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(currentStackMedicationClassIdsProvider.future),
        throwsA(isA<StateError>()),
      );
    },
  );
  for (final entry in [
    ['6448', 'class:antipsychotics', 'lithium'],
    ['4845', 'class:nsaids', ''],
    ['2473', 'class:nsaids', ''],
    ['6703', 'class:oral_contraceptives', ''],
    ['5640', '', 'nsaids'],
    ['999999', 'class:nsaids', 'nsaids'],
  ]) {
    test('refreshes stored medication class for ${entry[0]}', () async {
      final container = ProviderContainer(
        overrides: [
          interactionDatabaseProvider.overrideWithValue(database),
          activeStackProvider.overrideWith(
            (ref) async => [
              _row(
                id: entry[0],
                type: 'medication',
                rxcui: entry[0],
                drugClassesCol: entry[1].isEmpty ? '[]' : '["${entry[1]}"]',
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        await container.read(currentStackMedicationClassIdsProvider.future),
        entry[2].isEmpty ? isEmpty : equals({entry[2]}),
      );
    });
  }
  for (final ingredients in ['["4845","5640"]', '["6448","5093"]']) {
    test('preserves positive classes in combination $ingredients', () async {
      final container = ProviderContainer(
        overrides: [
          interactionDatabaseProvider.overrideWithValue(database),
          activeStackProvider.overrideWith(
            (ref) async => [
              _row(
                id: 'combination',
                type: 'medication',
                ingredientRxcuisCol: ingredients,
                drugClassesCol: ingredients.contains('5640')
                    ? '["class:nsaids"]'
                    : '["class:antipsychotics"]',
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        await container.read(currentStackMedicationClassIdsProvider.future),
        ingredients.contains('5640')
            ? {'nsaids'}
            : {'lithium', 'antipsychotics'},
      );
    });
  }
  test(
    'crosswalks medication drug classes and ignores supplement rows',
    () async {
      final container = ProviderContainer(
        overrides: [
          interactionDatabaseProvider.overrideWithValue(database),
          activeStackProvider.overrideWith(
            (ref) async => [
              // Stack rows store the `class:*` interaction-bridge vocab.
              _row(
                id: 'aspirin',
                type: 'medication',
                drugClassesCol: '["class:antiplatelet_agents"]',
              ),
              _row(
                id: 'ibuprofen',
                type: 'medication',
                drugClassesCol: '["class:nsaids"]',
              ),
              _row(
                id: 'vitamin-d',
                type: 'supplement',
                drugClassesCol: '["class:should_be_ignored"]',
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      final classes = await container.read(
        currentStackMedicationClassIdsProvider.future,
      );
      // antiplatelet_agents is crosswalked to the profile vocab; nsaids fails
      // open as `class:`-stripped pass-through; the supplement row is excluded.
      expect(classes, containsAll(<String>['antiplatelets', 'nsaids']));
      expect(classes, isNot(contains('should_be_ignored')));
      expect(classes, isNot(contains('class:antiplatelet_agents')));
    },
  );

  test('empty when the stack has no medications', () async {
    final container = ProviderContainer(
      overrides: [
        activeStackProvider.overrideWith(
          (ref) async => [
            _row(id: 'vitamin-d', type: 'supplement', drugClassesCol: '["x"]'),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    final classes = await container.read(
      currentStackMedicationClassIdsProvider.future,
    );
    expect(classes, isEmpty);
  });
}
