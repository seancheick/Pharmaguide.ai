import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_safety_providers.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
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

/// Every id this device knows the user's medications by: RxCUIs, `class:*`
/// ids and profile drug-class ids. For exact comparison on the device only;
/// this must never be sent anywhere. [isComplete] is false when part of it could
/// not be read: what is known still matches, but a miss can't count as a clear.
/// Failures here report fixed text: a database error writes its bound values.
final localMedicationIdentityProvider =
    FutureProvider<({Set<String> ids, bool isComplete})>((ref) async {
      final stack = await ref.watch(activeStackProvider.future);
      final ids = <String>{};
      var isComplete = true;
      try {
        final profile = await ref.watch(loadedProfileProvider.future);
        ids.addAll(profile.drugClassesForEvaluator);
      } on Object catch (_, st) {
        // The stack still identifies medications; losing the profile's class picks
        // must not stop a match on what the stack does know.
        isComplete = false;
        CrashReportingService().recordError(
          StateError('The profile could not be read for medication identity.'),
          st,
          fatal: false,
          hint: 'medication_identity:profile_unavailable',
        );
      }
      for (final row in stack.where((entry) => entry.type == 'medication')) {
        final snapshot = MedicationIdentitySnapshot.fromStackRow(row);
        ids.addAll([
          ?snapshot.rxcui,
          ?snapshot.genericRxcui,
          ...snapshot.ingredientRxcuis,
        ]);
        try {
          final resolution =
              await MedicationClassBridge(
                db: ref.read(interactionDatabaseProvider),
              ).resolve(
                selectedRxcui: snapshot.rxcui,
                genericRxcui: snapshot.genericRxcui,
                ingredientRxcuis: snapshot.ingredientRxcuis,
                runtimeClassIds: snapshot.drugClassIds,
              );
          // Not the row's saved classes: the bridge has dropped any the data excludes.
          ids
            ..addAll(resolution.rxcuis)
            ..addAll(resolution.mergedInteractionClassIds)
            ..addAll(resolution.profileGateClassIds);
        } on Object catch (_, st) {
          // Same reason: the ids saved on the row remain usable.
          ids.addAll(snapshot.drugClassIds);
          isComplete = false;
          CrashReportingService().recordError(
            StateError('The medication class bridge could not be read.'),
            st,
            fatal: false,
            hint: 'medication_identity:class_bridge_unavailable',
          );
        }
      }
      return (ids: Set<String>.unmodifiable(ids), isComplete: isComplete);
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
