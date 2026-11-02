import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';

void main() {
  const inCatalog = 'in-catalog';
  const missing = 'missing';
  late Directory folder;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('nutrient_skips_');
    addTearDown(() => folder.delete(recursive: true));
  });

  File file(String name) => File(p.join(folder.path, name));

  Future<ProviderContainer> containerWith({
    required List<String> stackIds,
    Object? blobError,
  }) async {
    final userDb = UserDatabase(file('user.db'));
    final coreDb = CoreDatabase(file('core.db'));
    addTearDown(userDb.close);
    addTearDown(coreDb.close);
    await coreDb
        .into(coreDb.productsCore)
        .insert(
          ProductsCoreCompanion.insert(
            dsldId: inCatalog,
            productName: 'In catalog',
            productStatus: const Value('active'),
            exportVersion: 'test',
            exportedAt: '2026-11-02T00:00:00Z',
          ),
        );
    for (final id in stackIds) {
      await userDb.addToStack(
        UserStacksLocalCompanion.insert(id: id, name: id, dsldId: Value(id)),
      );
    }
    final container = ProviderContainer(
      overrides: [
        userDatabaseProvider.overrideWithValue(userDb),
        coreDatabaseProvider.overrideWithValue(coreDb),
        loadedProfileProvider.overrideWith((ref) async => const ProfileState()),
        detailBlobProvider.overrideWith((ref, id) async {
          if (blobError != null) throw blobError;
          return null;
        }),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('stackNutrientStatusesProvider', () {
    test('a product absent from the catalog is only incomplete', () async {
      final container = await containerWith(stackIds: [missing]);
      final result = await container.read(stackNutrientStatusesProvider.future);
      expect(result.incomplete, isTrue);
      expect(result.catalogProductSkipped, isFalse);
    });

    test('a catalog product whose details are absent is reported', () async {
      final container = await containerWith(stackIds: [inCatalog]);
      final result = await container.read(stackNutrientStatusesProvider.future);
      expect(result.incomplete, isTrue);
      expect(result.catalogProductSkipped, isTrue);
    });

    test('a catalog product whose details failed is reported', () async {
      final container = await containerWith(
        stackIds: [inCatalog],
        blobError: StateError('offline'),
      );
      final result = await container.read(stackNutrientStatusesProvider.future);
      expect(result.catalogProductSkipped, isTrue);
    });

    test('the gap is reported beside a missing product', () async {
      final container = await containerWith(stackIds: [missing, inCatalog]);
      final result = await container.read(stackNutrientStatusesProvider.future);
      expect(result.catalogProductSkipped, isTrue);
    });
  });

  test('the stack report carries the gap to the banner', () async {
    final interactionDb = InteractionDatabase(file('interaction.db'));
    final coreDb = CoreDatabase(file('core.db'));
    addTearDown(interactionDb.close);
    addTearDown(coreDb.close);
    final container = ProviderContainer(
      overrides: [
        coreDatabaseProvider.overrideWithValue(coreDb),
        interactionDatabaseProvider.overrideWithValue(interactionDb),
        activeStackProvider.overrideWith(
          (ref) async => [
            UserStacksLocalData(
              id: 'one',
              type: 'supplement',
              name: 'One',
              dsldId: inCatalog,
              addedAt: DateTime.utc(2026, 11, 2),
              clientUpdatedAt: DateTime.utc(2026, 11, 2),
            ),
          ],
        ),
        loadedProfileProvider.overrideWith((ref) async => const ProfileState()),
        stackNutrientStatusesProvider.overrideWith(
          (ref) async => const StackNutrientStatuses(
            statuses: [],
            incomplete: true,
            catalogProductSkipped: true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final report = await container.read(stackSafetyReportProvider.future);

    expect(report.catalogProductSkipped, isTrue);
    expect(report.coverageIncomplete, isTrue);
  });
}
