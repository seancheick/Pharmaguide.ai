import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';

UserStacksLocalData _row({
  required String id,
  required String type,
  String? drugClassesCol,
}) {
  final ts = DateTime.utc(2026, 5, 4, 12);
  return UserStacksLocalData(
    id: id,
    type: type,
    name: id,
    dsldId: null,
    rxcui: null,
    ingredientKeys: null,
    drugClassesCol: drugClassesCol,
    genericRxcui: null,
    ingredientRxcuisCol: null,
    dosage: null,
    frequency: null,
    addedAt: ts,
    clientUpdatedAt: ts,
    deletedAt: null,
    syncedAt: null,
  );
}

void main() {
  test('crosswalks medication drug classes and ignores supplement rows', () async {
    final container = ProviderContainer(
      overrides: [
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
  });

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
