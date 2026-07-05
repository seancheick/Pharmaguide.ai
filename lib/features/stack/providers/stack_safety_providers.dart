// Stack safety aggregations: the pre-add check, the aggregated banner
// report, recalled ingredients, and medication depletion matches.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart'
    as reference_data;
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_provider_helpers.dart';
import 'package:pharmaguide/services/health/product_health_facts.dart';
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/timing_evaluation_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

/// Result of the pre-add safety check ([safetyCheckForAddProvider]).
///
/// Carries the combined interaction/heuristic [results] AND a
/// [checksIncomplete] flag so the "Add to stack" sheet can distinguish
/// "every check ran and found nothing" (safe to affirm) from "one or more
/// checks could not run" (must hedge — an empty list is NOT a clean bill of
/// health). Under-warning is the dangerous failure on a medical surface, so
/// the sheet only renders the affirmative "Safe to add" state when
/// [isConfidentClear] is true.
class PreAddSafetyResult {
  const PreAddSafetyResult({
    required this.results,
    required this.checksIncomplete,
  });

  /// Fully-checked, nothing fired — the only state that may show the
  /// affirmative "Safe to add" banner. Also used for the trivially-safe
  /// short-circuits (empty stack / candidate not found).
  static const PreAddSafetyResult clear = PreAddSafetyResult(
    results: <InteractionResult>[],
    checksIncomplete: false,
  );

  /// Combined curated (supplement×supplement, medication×supplement) and
  /// heuristic (stim/sed, blood-thinner, duplicate-active) hits, deduped by
  /// result id.
  final List<InteractionResult> results;

  /// True when at least one check could not run to completion — interaction
  /// DB failure, medication normalization failure, or a stack product that
  /// could not hydrate. An empty [results] with this set means "not fully
  /// checked", never "all clear".
  final bool checksIncomplete;

  /// The single state that is safe to render as an affirmative "Safe to
  /// add": every check ran AND nothing fired.
  bool get isConfidentClear => results.isEmpty && !checksIncomplete;
}

/// Runs the full pre-add safety check for [dsldId] against the current
/// stack — the same curated checks [stackSafetyReportProvider] runs for the
/// aggregated banner, pivoted for the single candidate product:
///
///   1. Curated supplement × supplement pair lookups
///      ([StackInteractionChecker.checkSupplementPairInteractions]).
///   2. Curated medication × supplement lookups
///      ([StackInteractionChecker.checkMedicationInteractions]) against the
///      stack's medications, normalized through the same
///      [MedicationClassBridge] path the report uses. This is the half that
///      was missing before — medications were dropped entirely (null
///      dsldId), so a warfarin × ginkgo bleeding-risk pair read as "Safe to
///      add".
///   3. The legacy fingerprint heuristic
///      ([StackInteractionChecker.checkSafety]) for stim/sed, blood-thinner,
///      and duplicate-active category warnings.
///
/// Results are combined and deduped by result id. If any check could not run
/// (DB unavailable, med normalization threw, a stack product failed to
/// hydrate) [PreAddSafetyResult.checksIncomplete] is set so the sheet hedges
/// instead of claiming "Safe to add".
///
/// Runs off the bundled core + interaction DBs only — no network. Fast
/// enough to await inside a "Verifying safety…" confirmation step.
final safetyCheckForAddProvider = FutureProvider.family
    .autoDispose<PreAddSafetyResult, String>((ref, dsldId) async {
      final coreDb = ref.watch(coreDatabaseProvider);

      final candidate = await coreDb.findById(dsldId);
      if (candidate == null) return PreAddSafetyResult.clear;

      // Mirror the report: depend on the active stack so any mutation
      // invalidates us, and split by type.
      final stack = await ref.watch(activeStackProvider.future);
      if (stack.isEmpty) return PreAddSafetyResult.clear;

      // Only needed to check a NON-empty stack — watch it after the
      // trivially-clear short-circuits so an empty-stack add never depends on
      // the interaction DB being present.
      final interactionDb = ref.watch(interactionDatabaseProvider);

      final supplementRows = stack
          .where((e) => e.type == 'supplement')
          .toList(growable: false);
      final medicationRows = stack
          .where((e) => e.type == 'medication')
          .toList(growable: false);

      var checksIncomplete = false;

      // Hydrate supplement stack rows to core products for the fingerprint
      // heuristic. A row that cannot hydrate is excluded from the heuristic,
      // so flag the result incomplete rather than silently under-checking.
      final stackProducts = <ProductsCoreData>[];
      for (final entry in supplementRows) {
        final id = entry.dsldId;
        if (id == null || id.isEmpty) continue;
        try {
          final product = await coreDb.findById(id);
          if (product != null) {
            stackProducts.add(product);
          } else {
            checksIncomplete = true;
          }
        } on Object {
          checksIncomplete = true;
        }
      }

      final candidateIds = canonicalIdsForProduct(candidate);
      final checker = StackInteractionChecker();
      final combined = <InteractionResult>[];
      final seenIds = <String>{};
      void addAll(Iterable<InteractionResult> hits) {
        for (final r in hits) {
          if (seenIds.add(r.id)) combined.add(r);
        }
      }

      // 1. Curated supplement × supplement pair lookups.
      if (candidateIds.isNotEmpty && supplementRows.isNotEmpty) {
        try {
          addAll(
            await checker.checkSupplementPairInteractions(
              newProductCanonicalIds: candidateIds,
              stackSupplements: supplementRows,
              db: interactionDb,
              newProductName: candidate.productName,
            ),
          );
        } on Object catch (e, st) {
          checksIncomplete = true;
          CrashReportingService().recordError(
            e,
            st,
            hint: 'safety_check_add:supplement_pairs_failed',
          );
        }
      }

      // 2. Curated medication × supplement lookups. Normalize the medication
      //    rows through the same bridge the report uses so brand/class
      //    resolution matches; an unresolvable medication marks the result
      //    incomplete (its class-level checks could not run).
      if (candidateIds.isNotEmpty && medicationRows.isNotEmpty) {
        try {
          final normalized = await _normalizeMedicationRowsForSafety(
            medicationRows,
            MedicationClassBridge(db: interactionDb),
          );
          if (normalized.identityIncomplete) checksIncomplete = true;
          addAll(
            await checker.checkMedicationInteractions(
              newProductCanonicalIds: candidateIds,
              stackMedications: normalized.rows,
              db: interactionDb,
              newProductName: candidate.productName,
            ),
          );
        } on Object catch (e, st) {
          checksIncomplete = true;
          CrashReportingService().recordError(
            e,
            st,
            hint: 'safety_check_add:medication_interactions_failed',
          );
        }
      }

      // 3. Legacy fingerprint heuristic (stim/sed, blood thinner, dup actives)
      //    for the candidate against every hydrated supplement in the stack.
      if (stackProducts.isNotEmpty) {
        bool flag(int? v) => v == 1;
        try {
          addAll(
            checker.checkSafety(
              newProductFingerprint: parseFingerprint(
                candidate.ingredientFingerprint,
              ),
              stackFingerprints: stackProducts
                  .map((p) => parseFingerprint(p.ingredientFingerprint))
                  .toList(growable: false),
              newContainsStimulants: flag(candidate.containsStimulants),
              newContainsSedatives: flag(candidate.containsSedatives),
              newContainsBloodThinners: flag(candidate.containsBloodThinners),
              stackContainsStimulants: stackProducts
                  .map((p) => flag(p.containsStimulants))
                  .toList(growable: false),
              stackContainsSedatives: stackProducts
                  .map((p) => flag(p.containsSedatives))
                  .toList(growable: false),
              stackContainsBloodThinners: stackProducts
                  .map((p) => flag(p.containsBloodThinners))
                  .toList(growable: false),
              stackProductNames: stackProducts
                  .map((p) => p.productName)
                  .toList(growable: false),
              newProductName: candidate.productName,
            ),
          );
        } on Object catch (e, st) {
          checksIncomplete = true;
          CrashReportingService().recordError(
            e,
            st,
            hint: 'safety_check_add:heuristic_failed',
          );
        }
      }

      return PreAddSafetyResult(
        results: combined,
        checksIncomplete: checksIncomplete,
      );
    });

/// Aggregated safety report for the current stack — drives the stack
/// screen's [StackSafetyBanner] (M4 §8.3).
///
/// Builds a [StackSafetyReport] by running all M4 curated checks across
/// the current stack and merging in the M1 nutrient statuses:
///
///   - Each supplement is "pivoted" against the rest of the stack to
///     populate `stackInteractions`. We dedupe by curated row id so a
///     pair like (A × B) only surfaces once even though both sides would
///     trigger the same lookup.
///   - Medications are fanned against every supplement via
///     [StackInteractionChecker.checkMedicationInteractions] to populate
///     `medicationInteractions`. Medications never pair-check against
///     each other here — drug×drug lookups are a follow-up when the
///     M2 bundle starts shipping curated drug×drug rows.
///   - The legacy heuristic `checkSafety` runs for every supplement
///     against the rest of the stack and populates `categoryWarnings`.
///   - [stackNutrientStatusesProvider] is awaited once and copied in
///     whole; [StackSafetyReport] already filters sub-warn tiers.
///
/// Empty stack → an empty report that the banner renders as
/// `SizedBox.shrink`. Errors in sub-checks are swallowed per-entry so a
/// single broken stack row can't tear down the whole banner.
final stackSafetyReportProvider = FutureProvider<StackSafetyReport>((
  ref,
) async {
  final coreDb = ref.watch(coreDatabaseProvider);
  final interactionDb = ref.watch(interactionDatabaseProvider);
  final refDataRepo = ref.watch(reference_data.referenceDataRepositoryProvider);

  // Take a dependency on the active stack so any mutation invalidates us.
  final stack = await ref.watch(activeStackProvider.future);
  if (stack.isEmpty) return const StackSafetyReport();

  // Nutrient statuses feed into the report as-is — the report's
  // `isEmpty` / `overallSeverity` getters already filter sub-warn tiers.
  // If the nutrient provider errors, we still want the interaction half
  // of the report to render, so we fall back to an empty list.
  var checksIncomplete = false;
  List<NutrientStatus> nutrientStatuses;
  try {
    nutrientStatuses = await ref.watch(stackNutrientStatusesProvider.future);
  } on Object catch (e, st) {
    checksIncomplete = true;
    CrashReportingService().recordError(
      e,
      st,
      hint: 'stack_safety:nutrient_statuses_failed',
    );
    nutrientStatuses = const <NutrientStatus>[];
  }

  final supplements = stack
      .where((e) => e.type == 'supplement')
      .toList(growable: false);
  final medications = stack
      .where((e) => e.type == 'medication')
      .toList(growable: false);
  final classBridge = MedicationClassBridge(db: interactionDb);
  var safetyMedications = medications;
  if (medications.isNotEmpty) {
    try {
      final normalized = await _normalizeMedicationRowsForSafety(
        medications,
        classBridge,
      );
      safetyMedications = normalized.rows;
      if (normalized.identityIncomplete) {
        // At least one medication could not be classified, so its class-level
        // interaction / profile-gate checks did not run — hedge the report.
        checksIncomplete = true;
      }
    } on Object catch (e, st) {
      checksIncomplete = true;
      CrashReportingService().recordError(
        e,
        st,
        hint: 'stack_safety:medication_class_bridge_failed',
      );
    }
  }

  final profile = await ref.watch(loadedProfileProvider.future);

  // Hydrate each supplement once — we need the core row for fingerprints
  // (category heuristics) and the ingredient_keys JSON for canonical ids.
  // Track low label-mapping coverage: below the 0.3 trust floor a
  // product's ingredients may never fire the interaction checks, so the
  // report must hedge rather than claim a clean result.
  var coverageIncomplete = false;
  final hydrated = <HydratedSupplement>[];
  for (final entry in supplements) {
    final id = entry.dsldId;
    if (id == null || id.isEmpty) continue;
    ProductsCoreData? product;
    try {
      product = await coreDb.findById(id);
    } on Exception {
      // Couldn't hydrate this product — it is excluded from every check
      // below, so the report must hedge rather than claim a clean result.
      coverageIncomplete = true;
      continue;
    }
    if (product == null) {
      coverageIncomplete = true;
      continue;
    }
    if (isLowCoverage(product.mappedCoverage)) coverageIncomplete = true;
    hydrated.add(HydratedSupplement(entry: entry, product: product));
  }

  final checker = StackInteractionChecker();

  // ---------------------------------------------------------------------------
  // 1. Supplement × supplement curated pair lookups.
  //    Pivot each supplement as "new" against the rest of the stack,
  //    then dedupe by curated row id across the whole pass. This
  //    mirrors `safetyCheckForAddProvider` but runs every supplement
  //    as if it were the newest.
  // ---------------------------------------------------------------------------
  final stackInteractions = <InteractionResult>[];
  final seenStackIds = <String>{};
  if (hydrated.length >= 2) {
    for (var i = 0; i < hydrated.length; i++) {
      final self = hydrated[i];
      final others = [
        for (var j = 0; j < hydrated.length; j++)
          if (j != i) hydrated[j].entry,
      ];
      final canonicalIds = canonicalIdsForProduct(self.product);
      if (canonicalIds.isEmpty) continue;
      List<InteractionResult> hits;
      try {
        hits = await checker.checkSupplementPairInteractions(
          newProductCanonicalIds: canonicalIds,
          stackSupplements: others,
          db: interactionDb,
          newProductName: self.entry.name,
        );
      } on Object catch (e, st) {
        checksIncomplete = true;
        CrashReportingService().recordError(
          e,
          st,
          hint: 'stack_safety:supplement_pairs_failed',
        );
        continue;
      }
      for (final r in hits) {
        if (seenStackIds.add(r.id)) stackInteractions.add(r);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 2. Medication × supplement curated lookups.
  //    For each supplement, fan against every medication. Dedupe by
  //    curated row id so a medication pair reached via both an rxcui
  //    and a parent drug_class only surfaces once.
  // ---------------------------------------------------------------------------
  final medicationInteractions = <InteractionResult>[];
  final seenMedIds = <String>{};
  if (hydrated.isNotEmpty && safetyMedications.isNotEmpty) {
    for (final self in hydrated) {
      final canonicalIds = canonicalIdsForProduct(self.product);
      if (canonicalIds.isEmpty) continue;
      List<InteractionResult> hits;
      try {
        hits = await checker.checkMedicationInteractions(
          newProductCanonicalIds: canonicalIds,
          stackMedications: safetyMedications,
          db: interactionDb,
          newProductName: self.entry.name,
        );
      } on Object catch (e, st) {
        checksIncomplete = true;
        CrashReportingService().recordError(
          e,
          st,
          hint: 'stack_safety:medication_supplement_failed',
        );
        continue;
      }
      for (final r in hits) {
        if (seenMedIds.add(r.id)) medicationInteractions.add(r);
      }
    }
  }
  if (safetyMedications.isNotEmpty) {
    try {
      final hits = await checker.checkMedicationFoodAdvisories(
        stackMedications: safetyMedications,
        db: interactionDb,
      );
      for (final r in hits) {
        if (seenMedIds.add(r.id)) medicationInteractions.add(r);
      }
    } on Object catch (e, st) {
      checksIncomplete = true;
      CrashReportingService().recordError(
        e,
        st,
        hint: 'stack_safety:food_advisories_failed',
      );
      // Food advisories are additive context; never let them block the
      // rest of the stack safety report.
    }
  }

  // ---------------------------------------------------------------------------
  // 3. Heuristic category checks (stim/sed, blood thinners). For the
  //    banner we run each supplement against the rest so the worst
  //    antagonism across the stack still surfaces; dedupe by the
  //    synthetic id the heuristic uses.
  // ---------------------------------------------------------------------------
  final categoryWarnings = <InteractionResult>[];
  final seenCatIds = <String>{};
  if (hydrated.length >= 2) {
    for (var i = 0; i < hydrated.length; i++) {
      final self = hydrated[i];
      final others = [
        for (var j = 0; j < hydrated.length; j++)
          if (j != i) hydrated[j],
      ];
      final newFp = parseFingerprint(self.product.ingredientFingerprint);
      final stackFps = others
          .map((o) => parseFingerprint(o.product.ingredientFingerprint))
          .toList(growable: false);

      bool flag(int? v) => v == 1;
      List<InteractionResult> hits;
      try {
        hits = checker.checkSafety(
          newProductFingerprint: newFp,
          stackFingerprints: stackFps,
          newContainsStimulants: flag(self.product.containsStimulants),
          newContainsSedatives: flag(self.product.containsSedatives),
          newContainsBloodThinners: flag(self.product.containsBloodThinners),
          stackContainsStimulants: others
              .map((o) => flag(o.product.containsStimulants))
              .toList(growable: false),
          stackContainsSedatives: others
              .map((o) => flag(o.product.containsSedatives))
              .toList(growable: false),
          stackContainsBloodThinners: others
              .map((o) => flag(o.product.containsBloodThinners))
              .toList(growable: false),
          stackProductNames: others
              .map((o) => o.entry.name)
              .toList(growable: false),
          newProductName: self.entry.name,
        );
      } on Object catch (e, st) {
        checksIncomplete = true;
        CrashReportingService().recordError(
          e,
          st,
          hint: 'stack_safety:heuristic_checks_failed',
        );
        continue;
      }
      for (final r in hits) {
        // Heuristic ids encode the partner index (`STACK_STIM_SED_$i`).
        // That's fine — we still want to dedupe the symmetric pair
        // (A→B and B→A would otherwise both fire), so we key on the
        // sorted name pair as a stable identity.
        final key = symmetricKey(r.agent1Name, r.agent2Name, r.id);
        if (seenCatIds.add(key)) categoryWarnings.add(r);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 4. Medication × medication pair checks (§0.2).
  //    Each medication is fanned against every other medication.
  //    Dedupe by curated row id.
  // ---------------------------------------------------------------------------
  final medicationPairInteractions = <InteractionResult>[];
  final seenMedPairIds = <String>{};
  if (safetyMedications.length >= 2) {
    for (var i = 0; i < safetyMedications.length; i++) {
      final self = [safetyMedications[i]];
      final others = [
        for (var j = 0; j < safetyMedications.length; j++)
          if (j != i) safetyMedications[j],
      ];
      List<InteractionResult> hits;
      try {
        hits = await checker.checkMedicationPairInteractions(
          newMedications: self,
          existingMedications: others,
          db: interactionDb,
        );
      } on Object catch (e, st) {
        checksIncomplete = true;
        CrashReportingService().recordError(
          e,
          st,
          hint: 'stack_safety:medication_pairs_failed',
        );
        continue;
      }
      for (final r in hits) {
        if (seenMedPairIds.add(r.id)) medicationPairInteractions.add(r);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 5. Medication × profile-gate rules.
  //    These are standalone medication-condition/profile warnings evaluated
  //    through the same profile_gate engine used by product warnings.
  // ---------------------------------------------------------------------------
  var medicationProfileWarnings = const <MedicationProfileWarning>[];
  if (safetyMedications.isNotEmpty) {
    try {
      final rulesData = await refDataRepo.loadMedicationProfileGateRules();
      final rules = MedicationProfileGateRule.listFromJson(rulesData);
      if (rules.isNotEmpty) {
        const evaluator = MedicationProfileGateEvaluator();
        final warnings = <MedicationProfileWarning>[];
        for (final med in safetyMedications) {
          final snapshot = MedicationIdentitySnapshot.fromStackRow(med);
          final resolution = await classBridge.resolve(
            selectedRxcui: snapshot.rxcui,
            genericRxcui: snapshot.genericRxcui,
            ingredientRxcuis: snapshot.ingredientRxcuis,
            runtimeClassIds: snapshot.drugClassIds,
          );
          warnings.addAll(
            evaluator.evaluate(
              rules: rules,
              medicationName: med.name,
              medicationProfileGateClassIds: resolution.profileGateClassIds
                  .toSet(),
              userConditions: profile.conditionsForEvaluator.toSet(),
              userProfileFlags: profile.evaluatorProfileFlags,
            ),
          );
        }
        medicationProfileWarnings = warnings;
      }
    } on Object catch (e, st) {
      checksIncomplete = true;
      CrashReportingService().recordError(
        e,
        st,
        hint: 'stack_safety:medication_profile_gate_failed',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 6. Timing optimization evaluation.
  //    Cross-reference the stack's ingredient tags and medication names
  //    against timing_rules.json to produce actionable timing advice.
  // ---------------------------------------------------------------------------
  List<TimingOptimization> timingOptimizations = const <TimingOptimization>[];
  try {
    final timingJson = await refDataRepo.loadTimingRules();
    final timingService = TimingEvaluationService.fromJson(timingJson);

    // Build supplement tag map: product_name → Set<canonical_tag>.
    final supplementTags = <String, Set<String>>{};
    for (final h in hydrated) {
      final tags = ingredientTagsForProduct(h.product);
      if (tags.isNotEmpty) {
        supplementTags[h.entry.name] = tags;
      }
    }

    // Collect medication display names.
    final medicationNames = safetyMedications
        .map((m) => m.name)
        .toList(growable: false);

    // Per-nutrient total doses (mg only) for dose-gated timing rules — reuse
    // the already-computed nutrient totals so there's no extra blob fetch.
    // Non-mg units (mcg/IU) are skipped; their rules fail open.
    final ingredientDosesMg = <String, double>{};
    for (final status in nutrientStatuses) {
      final total = status.total;
      if (total.unit.toLowerCase() == 'mg') {
        ingredientDosesMg[total.canonicalId.toLowerCase()] = total.totalAmount;
      }
    }

    timingOptimizations = timingService.evaluateStack(
      supplementTags: supplementTags,
      medicationNames: medicationNames,
      ingredientDosesMg: ingredientDosesMg,
    );
  } on Object catch (e, st) {
    checksIncomplete = true;
    CrashReportingService().recordError(
      e,
      st,
      hint: 'stack_safety:timing_failed',
    );
    // Timing is advisory — never let it crash the safety report.
    timingOptimizations = const <TimingOptimization>[];
  }

  return StackSafetyReport(
    nutrientStatuses: nutrientStatuses,
    stackInteractions: stackInteractions,
    medicationInteractions: medicationInteractions,
    medicationPairInteractions: medicationPairInteractions,
    medicationProfileWarnings: medicationProfileWarnings,
    categoryWarnings: categoryWarnings,
    timingOptimizations: timingOptimizations,
    coverageIncomplete: coverageIncomplete,
    checksIncomplete: checksIncomplete,
  );
});

Future<({List<UserStacksLocalData> rows, bool identityIncomplete})>
_normalizeMedicationRowsForSafety(
  List<UserStacksLocalData> medications,
  MedicationClassBridge bridge,
) async {
  final out = <UserStacksLocalData>[];
  var identityIncomplete = false;
  for (final med in medications) {
    final snapshot = MedicationIdentitySnapshot.fromStackRow(med);
    final resolution = await bridge.resolve(
      selectedRxcui: snapshot.rxcui,
      genericRxcui: snapshot.genericRxcui,
      ingredientRxcuis: snapshot.ingredientRxcuis,
      runtimeClassIds: snapshot.drugClassIds,
    );
    final mergedClasses = resolution.mergedInteractionClassIds;
    if (mergedClasses.isEmpty) {
      // No drug class could be resolved for this medication from any source
      // (e.g. a brand RxCUI like Advil saved before its ingredient + classes
      // hydrated, then evaluated offline). Class-level interaction and
      // profile-gate checks (NSAID-in-pregnancy, etc.) cannot run for it, so
      // flag the result as incomplete rather than letting the stack render a
      // false "all clear". This is the generic safety net for every
      // unresolvable medication, not just the Motrin alias special-case.
      identityIncomplete = true;
    }
    final nextClassesJson = mergedClasses.isEmpty
        ? null
        : jsonEncode(mergedClasses);
    if (nextClassesJson == med.drugClassesCol) {
      out.add(med);
    } else {
      out.add(med.copyWith(drugClassesCol: Value(nextClassesJson)));
    }
  }
  return (rows: out, identityIncomplete: identityIncomplete);
}

/// Recall detection result: the [report] plus an [incomplete] flag set when
/// the banned/recalled asset could not be loaded.
///
/// A load failure used to be swallowed silently — recall detection would
/// disable itself and the stack read "all clear", so an FDA-recalled product
/// went un-flagged. Now the failure is recorded (CrashReportingService) and
/// [incomplete] lets the banner hedge instead of implying "no recalls".
///
/// This is the real worker; [recalledIngredientsReportProvider] is a thin
/// view kept unchanged for consumers that only need the report.
final recalledIngredientsCheckProvider =
    FutureProvider<({RecalledIngredientsReport report, bool incomplete})>((
      ref,
    ) async {
      final coreDb = ref.watch(coreDatabaseProvider);
      // Read the repo via the provider so tests can override the asset source.
      // Sprint 27.6 added this indirection to enable integration tests of
      // the scan→flag path without needing to bundle fixture assets.
      final refDataRepo = ref.watch(
        reference_data.referenceDataRepositoryProvider,
      );

      // Take a dependency on the active stack so any mutation invalidates us.
      final stack = await ref.watch(activeStackProvider.future);
      if (stack.isEmpty) {
        return (report: RecalledIngredientsReport.empty(), incomplete: false);
      }

      final supplements = stack
          .where((e) => e.type == 'supplement')
          .toList(growable: false);
      if (supplements.isEmpty) {
        return (report: RecalledIngredientsReport.empty(), incomplete: false);
      }

      // Load banned/recalled ingredients data. A failure here disables recall
      // detection for the whole stack — record it and flag the result incomplete
      // so the banner hedges rather than implying "no recalls".
      final Map<String, dynamic> recallData;
      try {
        recallData = await refDataRepo.loadBannedRecalledIngredients();
      } on Object catch (e, st) {
        CrashReportingService().recordError(
          e,
          st,
          hint: 'stack_safety:recalled_ingredients_load_failed',
        );
        return (report: RecalledIngredientsReport.empty(), incomplete: true);
      }

      final recalledRaw = recallData['recalled_ingredients'];
      final recalledList = recalledRaw is List ? recalledRaw : null;
      if (recalledList == null || recalledList.isEmpty) {
        return (report: RecalledIngredientsReport.empty(), incomplete: false);
      }

      // Build a map of canonical_id → RecalledIngredientAlert for fast lookup.
      final recalledMap = <String, RecalledIngredientAlert>{};
      for (final recallJson in recalledList) {
        if (recallJson is! Map) continue;
        final recall = Map<String, dynamic>.from(recallJson);
        final canonicalId = recall['canonical_id'] as String?;
        if (canonicalId == null) continue;

        final commonNames =
            (recall['common_names'] as List<dynamic>?)
                ?.map((c) => c.toString())
                .toList() ??
            const <String>[];
        final recallStatus = recall['recall_status'] as String? ?? 'warning';
        final regulatoryBasis = recall['regulatory_basis'] as String? ?? '';
        final reason = recall['reason'] as String? ?? '';
        final effectiveDate = recall['effective_date'] as String? ?? '';
        final severity = recall['severity'] as String? ?? 'major';
        final safetyWarning = recall['safety_warning'] as String? ?? '';
        final safetyWarningOneLiner =
            recall['safety_warning_one_liner'] as String? ?? '';
        final banContext = recall['ban_context'] as String? ?? '';

        recalledMap[canonicalId] = RecalledIngredientAlert(
          canonicalId: canonicalId,
          commonNames: commonNames,
          recallStatus: recallStatus,
          regulatoryBasis: regulatoryBasis,
          reason: reason,
          effectiveDate: effectiveDate,
          severity: severity,
          safetyWarning: safetyWarning,
          safetyWarningOneLiner: safetyWarningOneLiner,
          banContext: banContext,
        );
      }

      // Check each supplement for recalled ingredients.
      final violations = <RecalledIngredientViolation>[];
      for (final entry in supplements) {
        final productId = entry.dsldId;
        if (productId == null || productId.isEmpty) continue;

        ProductsCoreData? product;
        try {
          product = await coreDb.findById(productId);
        } on Exception {
          continue;
        }
        if (product == null) continue;

        // Check if product has the recalled flag or contains recalled ingredients.
        final hasRecallFlag = (product.hasRecalledIngredient ?? 0) == 1;
        final canonicalIds = canonicalIdsForProduct(product);
        final recalledIngredients = <RecalledIngredientAlert>[];

        for (final cid in canonicalIds) {
          if (recalledMap.containsKey(cid)) {
            recalledIngredients.add(recalledMap[cid]!);
          }
        }

        // If the product is flagged or contains recalled ingredients, add violation.
        if (hasRecallFlag || recalledIngredients.isNotEmpty) {
          violations.add(
            RecalledIngredientViolation(
              productDsldId: productId,
              productName: entry.name,
              brandName: product.brandName ?? '',
              recalledIngredients: recalledIngredients,
            ),
          );
        }
      }

      return (
        report: RecalledIngredientsReport(violations: violations),
        incomplete: false,
      );
    });

/// Recall detection report for the active stack. Thin view over
/// [recalledIngredientsCheckProvider] — kept as its own provider (same name
/// + type) so existing consumers (home, share-report, stack intelligence)
/// are unchanged. The stack's recall banner watches the check provider
/// directly to read the `incomplete` hedge.
final recalledIngredientsReportProvider =
    FutureProvider<RecalledIngredientsReport>((ref) async {
      final check = await ref.watch(recalledIngredientsCheckProvider.future);
      return check.report;
    });

/// Depletion checker — matches medications against known nutrient
/// depletions and highlights which ones the user's supplement stack
/// already covers.
final depletionReportProvider = FutureProvider<List<DepletionMatch>>((
  ref,
) async {
  final stack = await ref.watch(activeStackProvider.future);
  final medications = stack
      .where((e) => e.type == 'medication')
      .map(
        (e) => DepletionMedicationIdentity(
          name: e.name,
          rxcui: e.rxcui,
          genericRxcui: e.genericRxcui,
          ingredientRxcuis: _decodeStackStringList(e.ingredientRxcuisCol),
          drugClassIds: _decodeStackStringList(e.drugClassesCol),
        ),
      )
      .toList(growable: false);

  if (medications.isEmpty) return const [];

  final repo = ref.watch(reference_data.referenceDataRepositoryProvider);
  final depletionsData = await repo.loadMedicationDepletions();

  // Build canonical IDs and real dose rows from the supplement stack.
  // `keyIngredientTags` is a useful presence fallback, but depletion
  // thresholds need actual Supplement Facts active rows from the detail blob.
  // Do not use the RDA/UL nutrient view here: it intentionally skips some
  // rows that still matter for depletion coverage (CoQ10, melatonin, etc.).
  final coreDb = ref.watch(coreDatabaseProvider);
  final supplements = stack.where((e) => e.type == 'supplement').toList();
  final coveredIds = <String>{};
  final nutrientItems = <StackItemNutrients>[];
  for (final supp in supplements) {
    if (supp.dsldId == null) continue;
    ProductsCoreData? product;
    try {
      product = await coreDb.findById(supp.dsldId!);
    } on Object {
      continue;
    }
    final keyIngredientTags = product?.keyIngredientTags;
    if (keyIngredientTags != null) {
      try {
        final tags = jsonDecode(keyIngredientTags);
        if (tags is List) {
          for (final tag in tags) {
            coveredIds.add(tag.toString().toLowerCase());
          }
        }
      } on FormatException {
        // skip
      }
    }
    Map<String, dynamic>? blob;
    try {
      blob = await ref.watch(detailBlobProvider(supp.dsldId!).future);
    } on Object {
      blob = null;
    }
    if (blob == null) continue;

    final nutrients = ProductHealthFacts.fromDetailBlob(blob).activeIngredients;
    if (nutrients.isEmpty) continue;
    nutrientItems.add(
      StackItemNutrients(
        stackEntryId: supp.id,
        productName: supp.name,
        ingredients: nutrients,
      ),
    );
  }

  final stackDoses = <StackSupplementDose>[];
  if (nutrientItems.isNotEmpty) {
    const aggregator = StackNutrientAggregator();
    final totals = aggregator.aggregate(nutrientItems);
    for (final total in totals.values) {
      if (total.totalAmount <= 0 || total.unit.isEmpty) continue;
      coveredIds.add(total.canonicalId.toLowerCase());
      stackDoses.add(
        StackSupplementDose(
          canonicalId: total.canonicalId,
          doseAmount: total.totalAmount,
          doseUnit: total.unit,
        ),
      );
    }
  }

  final checker = DepletionChecker();
  return checker.check(
    medications: const [],
    medicationIdentities: medications,
    depletionsData: depletionsData,
    stackCanonicalIds: coveredIds,
    stackDoses: stackDoses,
  );
});

/// Drug-class ids resolved for the user's CURRENT-STACK medications — the
/// SAME already-resolved source stack safety and depletion consume
/// (`drugClassesCol` on `type == 'medication'` rows, populated by the class
/// bridge at add-time). Exposed so product detail can gate its
/// pipeline-authored drug-interaction warnings on the meds a user actually
/// added, not just the profile picker chips. NO re-mapping here — this reads
/// the classes the bridge already resolved, keeping one source of truth.
final currentStackMedicationClassIdsProvider = FutureProvider<Set<String>>((
  ref,
) async {
  final stack = await ref.watch(activeStackProvider.future);
  final out = <String>{};
  for (final e in stack) {
    if (e.type != 'medication') continue;
    out.addAll(_decodeStackStringList(e.drugClassesCol));
  }
  return out;
});

List<String> _decodeStackStringList(String? raw) {
  if (raw == null || raw.isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    for (final item in decoded) {
      final value = item?.toString().trim();
      if (value == null || value.isEmpty) continue;
      if (seen.add(value)) out.add(value);
    }
    return out;
  } on FormatException {
    return const <String>[];
  }
}
