import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/medication_identity_providers.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';

UserStacksLocalData _med({
  required String id,
  required String name,
  String? rxcui,
  String? genericRxcui,
  String? drugClasses,
}) {
  final now = DateTime.utc(2026, 6, 8);
  return UserStacksLocalData(
    id: id,
    type: 'medication',
    name: name,
    rxcui: rxcui,
    genericRxcui: genericRxcui,
    drugClassesCol: drugClasses,
    addedAt: now,
    clientUpdatedAt: now,
  );
}

void main() {
  test(
    'medicationIdentityAuditProvider counts saved identity quality',
    () async {
      final container = ProviderContainer(
        overrides: [
          activeStackProvider.overrideWith(
            (ref) async => [
              _med(
                id: 'complete',
                name: 'Complete',
                rxcui: '1',
                genericRxcui: '11',
                drugClasses: '["class:a"]',
              ),
              _med(id: 'exact', name: 'Exact only', rxcui: '2'),
              _med(id: 'class', name: 'Class only', drugClasses: '["class:b"]'),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      final audit = await container.read(
        medicationIdentityAuditProvider.future,
      );

      expect(audit.total, 3);
      expect(audit.count(MedicationIdentityStatus.complete), 1);
      expect(audit.count(MedicationIdentityStatus.exactOnly), 1);
      expect(audit.count(MedicationIdentityStatus.classOnly), 1);
      expect(audit.hasIncomplete, isTrue);
    },
  );
}
