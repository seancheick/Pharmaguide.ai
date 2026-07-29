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

class MedicationIdentityAssessment {
  const MedicationIdentityAssessment({
    required this.snapshot,
    required this.curatedClassIds,
    required this.hasDirectRuleCoverage,
  });

  final MedicationIdentitySnapshot snapshot;
  final List<String> curatedClassIds;
  final bool hasDirectRuleCoverage;

  bool get hasReviewedCoverage =>
      curatedClassIds.isNotEmpty || hasDirectRuleCoverage;

  MedicationIdentityStatus get status {
    if (!hasReviewedCoverage) {
      return snapshot.hasAnyRxcui
          ? MedicationIdentityStatus.exactOnly
          : MedicationIdentityStatus.unresolved;
    }
    if (snapshot.hasGenericRxcui || snapshot.hasIngredientRxcuis) {
      return MedicationIdentityStatus.complete;
    }
    if (!snapshot.hasAnyRxcui && curatedClassIds.isNotEmpty) {
      return MedicationIdentityStatus.classOnly;
    }
    return MedicationIdentityStatus.partial;
  }
}

/// Audits the identity that can actually reach a reviewed interaction rule.
///
/// Saved RxClass ids are useful normalization evidence, but they are not
/// necessarily members of PharmaGuide's curated class map. Keeping this
/// assessment separate from [MedicationIdentitySnapshot] prevents an
/// arbitrary runtime class from producing a reassuring green match state.
final medicationIdentityAssessmentsProvider =
    FutureProvider<Map<String, MedicationIdentityAssessment>>((ref) async {
      final stack = await ref.watch(activeStackProvider.future);
      final db = ref.read(interactionDatabaseProvider);
      final bridge = MedicationClassBridge(db: db);
      final assessments = <String, MedicationIdentityAssessment>{};

      for (final row in stack.where((entry) => entry.type == 'medication')) {
        final snapshot = MedicationIdentitySnapshot.fromStackRow(row);
        final resolution = await bridge.resolve(
          selectedRxcui: snapshot.rxcui,
          genericRxcui: snapshot.genericRxcui,
          ingredientRxcuis: snapshot.ingredientRxcuis,
          runtimeClassIds: snapshot.drugClassIds,
        );

        var hasDirectRuleCoverage = false;
        final rxcuis = <String>{
          if (snapshot.rxcui case final value?) value,
          if (snapshot.genericRxcui case final value?) value,
          ...snapshot.ingredientRxcuis,
        };
        for (final rxcui in rxcuis) {
          if ((await db.lookupByRxcui(rxcui)).isNotEmpty) {
            hasDirectRuleCoverage = true;
            break;
          }
        }

        assessments[row.id] = MedicationIdentityAssessment(
          snapshot: snapshot,
          curatedClassIds: resolution.curatedInteractionClassIds,
          hasDirectRuleCoverage: hasDirectRuleCoverage,
        );
      }
      return assessments;
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
    final assessments = await ref.watch(
      medicationIdentityAssessmentsProvider.future,
    );
    final counts = <MedicationIdentityStatus, int>{};
    for (final assessment in assessments.values) {
      final status = assessment.status;
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return MedicationIdentityAudit(counts);
  },
);
