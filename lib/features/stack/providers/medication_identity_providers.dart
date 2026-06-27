import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';
import 'package:pharmaguide/services/medications/medication_identity_hydrator.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';
import 'package:pharmaguide/services/medications/rxnorm_providers.dart';

final medicationIdentityHydrationProvider = FutureProvider<int>((ref) async {
  await ref.watch(activeStackProvider.future);
  final hydrator = MedicationIdentityHydrator(
    userDb: ref.read(userDatabaseProvider),
    rxNorm: ref.read(rxNormApiServiceProvider),
    classBridge: MedicationClassBridge(
      db: ref.read(interactionDatabaseProvider),
    ),
  );
  final updated = await hydrator.rehydrateActiveStackMedications();
  if (updated > 0) {
    ref.invalidate(activeStackProvider);
    ref.invalidate(stackSafetyReportProvider);
    ref.invalidate(depletionReportProvider);
  }
  return updated;
});

class MedicationIdentityAudit {
  final Map<MedicationIdentityStatus, int> counts;

  const MedicationIdentityAudit(this.counts);

  int count(MedicationIdentityStatus status) => counts[status] ?? 0;

  int get total => counts.values.fold(0, (sum, value) => sum + value);

  bool get hasIncomplete =>
      count(MedicationIdentityStatus.partial) > 0 ||
      count(MedicationIdentityStatus.exactOnly) > 0 ||
      count(MedicationIdentityStatus.unresolved) > 0;
}

final medicationIdentityAuditProvider = FutureProvider<MedicationIdentityAudit>(
  (ref) async {
    final stack = await ref.watch(activeStackProvider.future);
    final counts = <MedicationIdentityStatus, int>{};
    for (final row in stack.where((e) => e.type == 'medication')) {
      final status = MedicationIdentitySnapshot.fromStackRow(row).status;
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return MedicationIdentityAudit(counts);
  },
);
