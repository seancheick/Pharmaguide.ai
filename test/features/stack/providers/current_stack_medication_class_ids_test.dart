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
  test('unions medication drug classes and ignores supplement rows', () async {
    final container = ProviderContainer(
      overrides: [
        activeStackProvider.overrideWith(
          (ref) async => [
            _row(
              id: 'warfarin',
              type: 'medication',
              drugClassesCol: '["vitamin_k_antagonists","anticoagulants"]',
            ),
            _row(
              id: 'metformin',
              type: 'medication',
              drugClassesCol: '["diabetes_meds"]',
            ),
            _row(
              id: 'vitamin-d',
              type: 'supplement',
              drugClassesCol: '["should_be_ignored"]',
            ),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    final classes = await container.read(
      currentStackMedicationClassIdsProvider.future,
    );
    expect(
      classes,
      containsAll(<String>[
        'vitamin_k_antagonists',
        'anticoagulants',
        'diabetes_meds',
      ]),
    );
    expect(classes, isNot(contains('should_be_ignored')));
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
