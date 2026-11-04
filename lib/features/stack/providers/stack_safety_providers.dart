// Stack safety aggregations: the pre-add check, the aggregated banner
// report, recalled ingredients, and medication depletion matches.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pharmaguide/services/warnings/interaction_warning.dart';
import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/features/product_detail/allergen_match.dart';
import 'package:pharmaguide/features/product_detail/providers/profile_warning_rule_provider.dart';
import 'package:pharmaguide/features/product_detail/v2/warnings_pipeline.dart';
import 'package:pharmaguide/services/warnings/profile_gate_summary_filter.dart';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/core/utils/product_canonical_ids.dart'
    show normalizeCanonicalId, canonicalIdsFromJsonString;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/providers/reference_data_provider.dart'
    as reference_data;
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_provider_helpers.dart';
import 'package:pharmaguide/features/stack/providers/synergy_report_provider.dart';
import 'package:pharmaguide/services/health/product_health_facts.dart';
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/depletion_watch.dart';
import 'package:pharmaguide/services/stack/medication_profile_gate_evaluator.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';
import 'package:pharmaguide/services/stack/stack_intelligence_engine.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/timing_evaluation_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

/// Result of the pre-add safety check ([safetyCheckForAddProvider]).
///
/// Carries the combined curated interaction [results] AND a
/// [checksIncomplete] flag so the "Add to stack" sheet can distinguish
/// "every check ran and found nothing" from "one or more checks could not
/// run" (must hedge — an empty list is NOT a clean bill of health), plus
/// [stackEmpty] for "there was nothing to check against". Under-warning is
/// the dangerous failure on a medical surface; even a full clear is shown as
/// "no known interactions", never as "safe".
class PreAddSafetyResult {
  const PreAddSafetyResult({
    required this.results,
    required this.checksIncomplete,
    this.stackEmpty = false,
  });

  /// Nothing in the stack to check the candidate against. Not a checked
  /// clear: the sheet says there was nothing to compare, never "safe".
  static const PreAddSafetyResult emptyStack = PreAddSafetyResult(
    results: <InteractionResult>[],
    checksIncomplete: false,
    stackEmpty: true,
  );

  /// The candidate is missing from the local catalog, so no check could run.
  static const PreAddSafetyResult notChecked = PreAddSafetyResult(
    results: <InteractionResult>[],
    checksIncomplete: true,
  );

  /// Curated supplement and medication interaction hits, deduped by rule ID.
  final List<InteractionResult> results;

  /// True when at least one check could not run to completion — interaction
  /// DB failure, medication normalization failure, a stack product that
  /// could not hydrate, or a candidate missing from the catalog. An empty
  /// [results] with this set means "not fully checked", never "all clear".
  final bool checksIncomplete;

  /// True when the stack was empty, so there was nothing to check against.
  final bool stackEmpty;

  /// Every check that applies ran and nothing fired. The sheet reports "no
  /// known interactions" — a finite curated list — and never "safe".
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
///
/// Results are combined and deduped by result id. If any check could not run
/// (DB unavailable, med normalization threw, a stack product failed to
/// hydrate, candidate missing from the catalog)
/// [PreAddSafetyResult.checksIncomplete] is set so the sheet hedges instead
/// of reporting a clear.
///
/// Runs off the bundled core + interaction DBs only — no network. Fast
/// enough to await inside a "Verifying safety…" confirmation step.
final safetyCheckForAddProvider = FutureProvider.family
    .autoDispose<PreAddSafetyResult, String>((ref, dsldId) async {
      final coreDb = ref.watch(coreDatabaseProvider);

      final candidate = await coreDb.findById(dsldId);

      // Mirror the report: depend on the active stack so any mutation
      // invalidates us, and split by type.
      final stack = await ref.watch(activeStackProvider.future);
      if (stack.isEmpty) return PreAddSafetyResult.emptyStack;
      // Missing from the local catalog: nothing could be checked, which is
      // not a clean result.
      if (candidate == null) return PreAddSafetyResult.notChecked;

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

      final candidateIds = canonicalIdsForProduct(candidate);
      var checksIncomplete =
          isLowCoverage(candidate.mappedCoverage) || candidateIds.isEmpty;

      // Missing catalog identities still make a check incomplete, even though
      // clinical findings come only from authored interaction rows.
      for (final entry in supplementRows) {
        final id = entry.dsldId;
        if (id == null || id.isEmpty) {
          checksIncomplete = true;
          continue;
        }
        if (canonicalIdsFromJsonString(entry.ingredientKeys).isEmpty) {
          checksIncomplete = true;
        }
        try {
          final product = await coreDb.findById(id);
          if (product == null ||
              isLowCoverage(product.mappedCoverage) ||
              canonicalIdsForProduct(product).isEmpty) {
            checksIncomplete = true;
          }
        } on Object {
          checksIncomplete = true;
        }
      }

      final checker = StackInteractionChecker();
      final pairwiseDoseResult = await _pairwiseDoseTotalsFor(
        ref,
        supplements: [
          (
            stackEntryId: 'candidate:$dsldId',
            productName: candidate.productName,
            dsldId: dsldId,
          ),
          for (final row in supplementRows)
            if (row.dsldId != null && row.dsldId!.isNotEmpty)
              (
                stackEntryId: row.id,
                productName: row.name,
                dsldId: row.dsldId!,
              ),
        ],
      );
      if (pairwiseDoseResult.incomplete) checksIncomplete = true;
      final pairwiseDoseTotals = pairwiseDoseResult.totals;
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
              stackDoseTotals: pairwiseDoseTotals,
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
              productForms:
                  pairwiseDoseResult.formsByProduct[dsldId] ?? const {},
              stackMedications: normalized.rows,
              db: interactionDb,
              newProductName: candidate.productName,
              stackDoseTotals: pairwiseDoseTotals,
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
  ProfileState? profile;
  try {
    profile = await ref.watch(loadedProfileProvider.future);
  } on Object {
    // Unknown is not an empty profile. Keep independent findings available,
    // but do not evaluate personalized rules against invented defaults.
    checksIncomplete = true;
  }
  // Set when the nutrient pass skipped a stack item; ORed into the report's
  // coverage flag below so the banner and the clinician report both hedge.
  var nutrientCoverageIncomplete = false;
  var catalogProductSkipped = false;
  List<NutrientStatus> nutrientStatuses;
  if (profile == null) {
    nutrientStatuses = const <NutrientStatus>[];
  } else {
    try {
      final result = await ref.watch(stackNutrientStatusesProvider.future);
      nutrientStatuses = result.statuses;
      nutrientCoverageIncomplete = result.incomplete;
      catalogProductSkipped = result.catalogProductSkipped;
    } on Object catch (e, st) {
      checksIncomplete = true;
      CrashReportingService().recordError(
        e,
        st,
        hint: 'stack_safety:nutrient_statuses_failed',
      );
      nutrientStatuses = const <NutrientStatus>[];
    }
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

  // Hydrate each supplement once for canonical interaction identities.
  // Track low label-mapping coverage: below the 0.3 trust floor a
  // product's ingredients may never fire the interaction checks, so the
  // report must hedge rather than claim a clean result.
  var coverageIncomplete = nutrientCoverageIncomplete;
  final limitedDataProducts = <LimitedDataProduct>[];
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
      checksIncomplete = true;
      catalogProductSkipped = true;
      continue;
    }
    if (product == null) {
      coverageIncomplete = true;
      continue;
    }
    if (isLowCoverage(product.mappedCoverage)) {
      coverageIncomplete = true;
      limitedDataProducts.add(
        LimitedDataProduct(
          entry.name,
          scoreUnavailableReason: product.scoreUnavailableReason,
        ),
      );
    }
    hydrated.add(HydratedSupplement(entry: entry, product: product));
  }

  final checker = StackInteractionChecker();
  final pairwiseDoseResult = await _pairwiseDoseTotalsFor(
    ref,
    supplements: [
      for (final h in hydrated)
        if (h.entry.dsldId != null && h.entry.dsldId!.isNotEmpty)
          (
            stackEntryId: h.entry.id,
            productName: h.entry.name,
            dsldId: h.entry.dsldId!,
          ),
    ],
  );
  if (pairwiseDoseResult.incomplete) checksIncomplete = true;
  final pairwiseDoseTotals = pairwiseDoseResult.totals;

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
          stackDoseTotals: pairwiseDoseTotals,
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

  // Product Detail owns profile gating, dose suppression and deduplication.
  // Carry its ordinary condition/allergen findings into the same Stack report.
  // Cumulative dose rules and global UL/regulatory findings keep their owners.
  if (hydrated.isNotEmpty && profile != null) {
    final conditions = profile.conditionsForEvaluator.toSet();
    var flags = <String>{};
    var flagsAvailable = true;
    var classes = profile.drugClassesForEvaluator.toSet();
    var classesAvailable = true;
    try {
      flags = await ref.watch(evaluatorProfileFlagsProvider.future);
    } on Object {
      flagsAvailable = false;
      checksIncomplete = true;
    }
    try {
      classes = {
        ...classes,
        ...await ref.watch(currentStackMedicationClassIdsProvider.future),
      };
    } on Object {
      classesAvailable = false;
      checksIncomplete = true;
    }
    for (final h in hydrated) {
      try {
        final blob = await ref.watch(
          detailBlobProvider(h.product.dsldId).future,
        );
        if (blob == null) {
          checksIncomplete = true;
          continue;
        }
        // Allergy matching remains available even if profile-rule resolution
        // fails. A failure must not discard another independently known concern.
        final rawAllergens = blob['allergens'];
        for (final match in matchAllergens(
          profile.allergensForEvaluator,
          rawAllergens is List ? rawAllergens : null,
        )) {
          final result = InteractionResult(
            id: 'ALLERGEN_${h.product.dsldId}_${match.id}_${match.presenceType}',
            type: InteractionType.conditionSupplement,
            severity: allergenPresenceSeverity(match.presenceType),
            evidenceLevel: EvidenceLevel.ungraded,
            agent1Name: h.entry.name,
            agent2Name: match.displayName,
            mechanism:
                '${allergenPresenceLabel(match.presenceType)}: ${match.displayName}${match.evidence == null ? '' : ' · ${match.evidence}'}',
            management: '',
            doseDependant: false,
            doseThreshold: null,
            sourceUrls: const [],
            source: InteractionSource.pipeline,
          );
          if (seenStackIds.add(result.id)) stackInteractions.add(result);
        }
        var resolved = const <InteractionWarning>[];
        try {
          resolved = await ref.watch(
            profileWarningRuleWarningsProvider(h.product.dsldId).future,
          );
        } on Object {
          // Match Product Detail: unavailable references cannot erase a
          // readable authored warning from the same blob.
          checksIncomplete = true;
        }
        final readableWarnings =
            [
                  ...parseBlobWarnings(
                    blob,
                    productStatus: h.product.productStatus,
                  ),
                  ...resolved,
                ]
                .where((warning) {
                  bool references(String key) {
                    for (final branch in ['requires', 'excludes']) {
                      final gate = warning.profileGate?[branch];
                      if (gate is Map &&
                          gate[key] is List &&
                          (gate[key] as List).isNotEmpty) {
                        return true;
                      }
                    }
                    return false;
                  }

                  if (!flagsAvailable && references('profile_flags_any')) {
                    return false;
                  }
                  if (!classesAvailable &&
                      (warning.drugClassIds.isNotEmpty ||
                          references('drug_classes_any'))) {
                    return false;
                  }
                  return true;
                })
                .toList(growable: false);
        final guarded = composeGuardedWarnings(
          // Remove only already-parsed warnings: retain all dose/form/UL facts
          // for the canonical Product Detail evaluator.
          detailBlob: {
            ...blob,
            'warnings': const <Map<String, dynamic>>[],
            'warnings_profile_gated': const <Map<String, dynamic>>[],
          },
          productStatus: h.product.productStatus,
          personalizedWarnings: readableWarnings,
          userConditions: conditions,
          userDrugClasses: classes,
          userProfileFlags: flags,
        );
        final warnings = partitionProfileWarnings(
          warnings: guarded,
          userConditions: conditions,
          userDrugClasses: classes,
          userProfileFlags: flags,
        ).profile;
        final facts = ProductHealthFacts.fromDetailBlob(blob);
        for (final warning in warnings) {
          final requires = warning.profileGate?['requires'];
          final hasConditionScope =
              warning.conditionIds.isNotEmpty ||
              (requires is Map &&
                  ['conditions_any', 'profile_flags_any'].any(
                    (key) =>
                        requires[key] is List &&
                        (requires[key] as List).isNotEmpty,
                  ));
          if (!hasConditionScope) continue;
          final context = resolveProfileGateProductContext(
            detailBlob: blob,
            warning: warning,
            healthFacts: facts,
          );
          if (!warning.matchesProfile(
            userConditions: conditions,
            userDrugClasses: classes,
            userProfileFlags: flags,
            productForm: context.productForm,
            nutrientForm: context.nutrientForm,
            nutrientForms: context.nutrientForms,
            dosePerDay: context.dosePerDay,
          )) {
            continue;
          }
          if (stackDoseThresholdRulesFromWarnings([warning]).isNotEmpty) {
            continue;
          }
          final body = warning.displayBody;
          final identity = warning.warningType == 'label_statement'
              ? body
              : jsonEncode([
                  warning.warningType,
                  warning.title,
                  warning.displayHeadline,
                  warning.displayModeDefault,
                  body,
                ]);
          final digest = sha256.convert(utf8.encode(identity));
          final prefix = warning.warningType == 'label_statement'
              ? 'LABEL'
              : 'PROFILE';
          final result = InteractionResult(
            id: '${prefix}_${h.product.dsldId}_$digest',
            type: InteractionType.conditionSupplement,
            severity: warning.severity,
            evidenceLevel: warning.evidenceLevel,
            agent1Name: h.entry.name,
            agent2Name: warning.title,
            mechanism: body,
            management: warning.management,
            doseDependant: false,
            doseThreshold: null,
            sourceUrls: warning.sourceUrls,
            source: InteractionSource.pipeline,
          );
          if (seenStackIds.add(result.id)) stackInteractions.add(result);
        }
      } on Object catch (error, trace) {
        checksIncomplete = true;
        CrashReportingService().recordError(
          error,
          trace,
          hint: 'stack_safety:product_profile_failed',
        );
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
          productForms:
              pairwiseDoseResult.formsByProduct[self.entry.dsldId] ?? const {},
          stackMedications: safetyMedications,
          db: interactionDb,
          newProductName: self.entry.name,
          stackDoseTotals: pairwiseDoseTotals,
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
  if (safetyMedications.isNotEmpty && profile != null) {
    try {
      final userProfileFlags = await ref.watch(
        evaluatorProfileFlagsProvider.future,
      );
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
              medicationIngredientRxcuis: {
                if (snapshot.genericRxcui == null &&
                    snapshot.ingredientRxcuis.isEmpty &&
                    snapshot.rxcui != null)
                  snapshot.rxcui!,
                if (snapshot.genericRxcui != null) snapshot.genericRxcui!,
                ...snapshot.ingredientRxcuis,
              },
              medicationContext: MedicationUseContext.fromStored(
                med.medicationContextCol,
              ),
              medicationProfileGateClassIds: resolution.profileGateClassIds
                  .toSet(),
              userConditions: profile.conditionsForEvaluator.toSet(),
              userProfileFlags: userProfileFlags,
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
  //    Cross-reference stack ingredient tags and reviewed medication RxCUIs
  //    against timing_rules.json to produce actionable timing advice.
  // ---------------------------------------------------------------------------
  List<TimingOptimization> timingOptimizations = const <TimingOptimization>[];
  try {
    final timingJson = await refDataRepo.loadTimingRules();
    final timingService = TimingEvaluationService.fromJson(timingJson);

    // Keep each physical stack row's id beside its display name and reviewed
    // matching identity. Display text is never used as an identifier.
    final timingStackItems = <TimingStackItem>[];
    for (final h in hydrated) {
      final tags = ingredientTagsForProduct(h.product);
      if (tags.isNotEmpty) {
        timingStackItems.add(
          TimingStackItem.supplement(
            stackEntryId: h.entry.id,
            displayName: h.entry.name,
            ingredientTags: tags,
          ),
        );
      }
    }

    // Preserve display names for attribution, but match medications only
    // through the saved RxNorm identity chain.
    for (final medication in safetyMedications) {
      final snapshot = MedicationIdentitySnapshot.fromStackRow(medication);
      final rxcuis = <String>{};
      for (final value in [
        snapshot.rxcui,
        snapshot.genericRxcui,
        ...snapshot.ingredientRxcuis,
      ]) {
        final normalized = value?.trim();
        if (normalized != null && normalized.isNotEmpty) {
          rxcuis.add(normalized);
        }
      }
      timingStackItems.add(
        TimingStackItem.medication(
          stackEntryId: medication.id,
          displayName: medication.name,
          medicationRxCuis: rxcuis,
        ),
      );
    }

    // Per-nutrient total doses (mg only) for the currently authored timing
    // gates — reuse
    // the already-computed nutrient totals so there's no extra blob fetch.
    // A gated rule with an unavailable or incompatible unit is suppressed;
    // dose-conditional copy never claims that an unevaluated floor was crossed.
    final ingredientDosesMg = <String, double>{};
    for (final status in nutrientStatuses) {
      final total = status.total;
      if (total.unit.toLowerCase() == 'mg') {
        ingredientDosesMg[total.canonicalId.toLowerCase()] = total.totalAmount;
      }
    }

    timingOptimizations = timingService.evaluateStack(
      stackItems: timingStackItems,
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
    timingOptimizations: timingOptimizations,
    coverageIncomplete: coverageIncomplete,
    checksIncomplete: checksIncomplete,
    catalogProductSkipped: catalogProductSkipped,
    limitedDataProducts: limitedDataProducts,
  );
});

Future<
  ({
    Map<String, StackDoseTotal> totals,
    bool incomplete,
    Map<String, Map<String, Set<String>?>> formsByProduct,
  })
>
_pairwiseDoseTotalsFor(
  Ref ref, {
  required List<({String stackEntryId, String productName, String dsldId})>
  supplements,
}) async {
  if (supplements.isEmpty) {
    return (
      totals: const <String, StackDoseTotal>{},
      incomplete: false,
      formsByProduct: const <String, Map<String, Set<String>?>>{},
    );
  }

  final items = <StackItemNutrients>[];
  final formsByProduct = <String, Map<String, Set<String>?>>{};
  var incomplete = false;
  for (final supplement in supplements) {
    Map<String, dynamic>? blob;
    try {
      blob = await ref.watch(detailBlobProvider(supplement.dsldId).future);
    } on Object {
      incomplete = true;
      continue;
    }
    if (blob == null) {
      incomplete = true;
      continue;
    }

    ProductHealthFacts facts;
    try {
      facts = ProductHealthFacts.fromDetailBlob(blob);
    } on Object {
      incomplete = true;
      continue;
    }
    formsByProduct[supplement.dsldId] = facts.matchedFormsByCanonical;
    final ingredients = facts.doseRowsForThresholds;
    if (ingredients.isEmpty) continue;

    items.add(
      StackItemNutrients(
        stackEntryId: supplement.stackEntryId,
        productName: supplement.productName,
        ingredients: ingredients,
      ),
    );
  }

  if (items.isEmpty) {
    return (
      totals: const <String, StackDoseTotal>{},
      incomplete: incomplete,
      formsByProduct: formsByProduct,
    );
  }
  return (
    totals: const StackDoseSummer().sum(items, formFactsComplete: !incomplete),
    incomplete: incomplete,
    formsByProduct: formsByProduct,
  );
}

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

/// Recall detection report for the active stack.
///
/// [RecalledIngredientsReport.incomplete] is set whenever a stack product could
/// not be inspected. Every consumer reads this same
/// report object, so Home, Stack, and clinician output cannot disagree about
/// whether the scan completed.
///
/// A failure used to be swallowed silently and returned as an empty report.
/// That made an unavailable check indistinguishable from a clean result.
final recalledIngredientsReportProvider =
    FutureProvider<RecalledIngredientsReport>((ref) async {
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
        return RecalledIngredientsReport.empty();
      }

      final supplements = stack
          .where((e) => e.type == 'supplement')
          .toList(growable: false);
      if (supplements.isEmpty) {
        return RecalledIngredientsReport.empty();
      }

      // The authored list only names the substance. The catalog flags below
      // decide whether a product is flagged, so a failure here is reported and
      // detection carries on without the names.
      var recalledList = const <dynamic>[];
      try {
        final recallData = await refDataRepo.loadBannedRecalledIngredients();
        final recalledRaw = recallData['recalled_ingredients'];
        if (recalledRaw is List) recalledList = recalledRaw;
      } on Object catch (e, st) {
        CrashReportingService().recordError(
          e,
          st,
          hint: 'stack_safety:recalled_ingredients_load_failed',
        );
      }

      // Index the authored records by INGREDIENT NAME, not by `canonical_id`.
      //
      // `canonical_id` is a record id (`BANNED_SIBUTRAMINE`, `ADULTERANT_
      // METFORMIN` — 17 distinct prefixes, 0 lowercase); a product's ids are
      // catalog ingredient ids (`sibutramine`). Keying on `canonical_id` and
      // testing it against product ids could never match, for any product.
      // `common_names` is the field that actually holds ingredient names, so
      // it is the real join key — folded through the catalog's single
      // canonicalizer so both sides of the comparison speak one dialect.
      //
      // Restricted to hard `banned` / `recalled` statuses. The asset also carries
      // `high_risk` / `watchlist` / `recalled` advisory tiers whose substances
      // (garcinia, yohimbe, CBD, red yeast rice) appear in hundreds of
      // products the pipeline deliberately does NOT block. Indexing those here
      // would let this surface invent a "banned" verdict the pipeline never
      // made.
      final bannedByIngredient = <String, RecalledIngredientAlert>{};
      final recalledByProductName = <String, RecalledIngredientAlert>{};
      for (final recallJson in recalledList) {
        if (recallJson is! Map) continue;
        final recall = Map<String, dynamic>.from(recallJson);
        final canonicalId = recall['canonical_id']?.toString().trim();
        if (canonicalId == null || canonicalId.isEmpty) continue;

        final rawCommonNames = recall['common_names'];
        final commonNames = rawCommonNames is List
            ? rawCommonNames
                  .map((value) => value.toString().trim())
                  .where((value) => value.isNotEmpty)
                  .toList(growable: false)
            : const <String>[];
        final recallStatus =
            recall['recall_status']?.toString().trim() ?? 'warning';
        final regulatoryBasis =
            recall['regulatory_basis']?.toString().trim() ?? '';
        final reason = recall['reason']?.toString().trim() ?? '';
        final effectiveDate = recall['effective_date']?.toString().trim() ?? '';
        final severity = recall['severity']?.toString().trim() ?? 'major';
        final safetyWarning = recall['safety_warning']?.toString().trim() ?? '';
        final safetyWarningOneLiner =
            recall['safety_warning_one_liner']?.toString().trim() ?? '';
        final banContext = recall['ban_context']?.toString().trim() ?? '';

        // `banned` and `recalled` both mean "not permitted / pulled". The
        // advisory tiers are excluded: `high_risk` alone accounts for all 203
        // of the unflagged matches measured against the shipped catalog
        // (garcinia, yohimbe, CBD, red yeast rice), and `watchlist` carries
        // softer severity semantics than a block deserves.
        if (recallStatus != 'banned' && recallStatus != 'recalled') continue;

        final alert = RecalledIngredientAlert(
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
        if (commonNames.isEmpty) continue;
        for (final name in commonNames) {
          final key = normalizeCanonicalId(name);
          if (key == null) continue;
          if (recallStatus == 'banned') {
            bannedByIngredient.putIfAbsent(key, () => alert);
          } else {
            recalledByProductName.putIfAbsent(key, () => alert);
          }
        }
      }

      // Check each supplement for recalled ingredients.
      final violations = <RecalledIngredientViolation>[];
      final notInCatalog = <String>[];
      final unreadableProducts = <String>[];
      var incomplete = false;
      for (final entry in supplements) {
        final productId = entry.dsldId;
        if (productId == null || productId.isEmpty) {
          incomplete = true;
          notInCatalog.add(entry.name);
          continue;
        }

        ProductsCoreData? product;
        try {
          product = await coreDb.findById(productId);
        } on Object catch (e, st) {
          incomplete = true;
          unreadableProducts.add(entry.name);
          CrashReportingService().recordError(
            e,
            st,
            hint: 'stack_safety:recalled_product_hydration_failed',
          );
          continue;
        }
        if (product == null) {
          incomplete = true;
          notInCatalog.add(entry.name);
          continue;
        }

        // ONE BRAIN: the pipeline decides WHETHER a product carries a banned
        // substance; this surface only decides how to say it. The app never
        // derives its own banned verdict — a name match on an unflagged
        // product is not a finding here, because the pipeline saw the same
        // ingredients and did not block it.
        //
        // `has_banned_substance` is the authoritative flag (currently 1 on
        // exactly the BLOCKED set). `has_recalled_ingredient` is read too so a
        // lot-specific recall still fires the moment the pipeline populates it
        // — it is 0 across the shipped catalog today, which is why it must not
        // be the only trigger.
        final hasBannedSubstance = (product.hasBannedSubstance ?? 0) == 1;
        final hasRecalledProduct = (product.hasRecalledIngredient ?? 0) == 1;
        if (!hasBannedSubstance && !hasRecalledProduct) continue;

        // Name the substance from the authored record when we can. A flagged
        // product with no matching record still warns — with the substance
        // name omitted rather than the whole violation dropped.
        final recalledIngredients = <RecalledIngredientAlert>[];
        final seenRecords = <String>{};
        if (hasBannedSubstance) {
          for (final cid in canonicalIdsForProduct(product)) {
            final alert = bannedByIngredient[cid];
            if (alert == null) continue;
            if (seenRecords.add(alert.canonicalId)) {
              recalledIngredients.add(alert);
            }
          }
        }
        if (hasRecalledProduct) {
          final productNames = <String?>[
            normalizeCanonicalId(entry.name),
            normalizeCanonicalId(product.productName),
          ];
          for (final name in productNames) {
            if (name == null) continue;
            final alert = recalledByProductName[name];
            if (alert == null) continue;
            if (seenRecords.add(alert.canonicalId)) {
              recalledIngredients.add(alert);
            }
          }
        }

        violations.add(
          RecalledIngredientViolation(
            productDsldId: productId,
            productName: entry.name,
            brandName: product.brandName ?? '',
            recalledIngredients: recalledIngredients,
            pipelineBannedSubstance: hasBannedSubstance,
            pipelineRecalledProduct: hasRecalledProduct,
          ),
        );
      }

      return RecalledIngredientsReport(
        violations: violations,
        incomplete: incomplete,
        notInCatalog: notInCatalog,
        unreadableProducts: unreadableProducts,
      );
    });

/// The single Stack Health presentation snapshot consumed by Home, Stack,
/// the hero warning, and the details sheet. Failed profile-dependent checks
/// remain incomplete while known independent findings stay in this shared
/// snapshot; individual surfaces never rebuild a different subset.
final stackHealthSnapshotProvider = FutureProvider<StackHealthSnapshot>((
  ref,
) async {
  final stack = await ref.watch(activeStackProvider.future);
  final safetyReport = await ref.watch(stackSafetyReportProvider.future);
  final recalledReport = await ref.watch(
    recalledIngredientsReportProvider.future,
  );
  final synergyReport = await ref.watch(synergyReportProvider.future);
  var doseChecksIncomplete = false;
  var doseThresholdAlerts = const <StackDoseThresholdAlert>[];
  var doseRulesUnread = false;
  try {
    doseThresholdAlerts = await ref.watch(
      stackDoseThresholdAlertsProvider.future,
    );
    doseRulesUnread = await ref.watch(stackDoseRulesUnreadProvider.future);
  } on Object {
    // A missing profile/dose assessment cannot erase independent pairwise
    // findings or catalog recalls. The shared snapshot still carries the gap.
    doseChecksIncomplete = true;
  }

  // Keep known findings available while the feed loads or fails; only a fully
  // readable verified feed can support the shared clean result. Readable cached
  // feeds remain usable offline, matching the product-page contract.
  final alertsAsync = ref.watch(safetyAlertMatchesProvider);
  // A dependency reload can mean a different stack or profile. Only AsyncData
  // (including a same-input refresh) belongs to the current matching context.
  final alerts = alertsAsync.asData?.value;
  return const StackIntelligenceEngine().summarizeFromReports(
    regulatorySafetyAlerts: alerts?.matches ?? const [],
    alertChecksIncomplete:
        doseChecksIncomplete ||
        alertsAsync.hasError ||
        alerts == null ||
        alerts.neverVerified ||
        !alerts.isDeviceComplete,
    doseRulesUnread: doseRulesUnread,
    stackSize: stack.length,
    safetyReport: safetyReport,
    recalledReport: recalledReport,
    synergyReport: synergyReport,
    doseThresholdAlerts: doseThresholdAlerts,
  );
});

/// Depletion checker — matches medications against known nutrient
/// depletions and highlights which ones the user's supplement stack
/// already covers.
/// Build the depletion matching identity for one stack medication row.
///
/// Shared by [depletionReportProvider] and [depletionWatchProvider] so the two
/// can never drift: a watch must describe exactly the relationship its card
/// renders.
DepletionMedicationIdentity _depletionIdentityFor(UserStacksLocalData e) {
  return DepletionMedicationIdentity(
    name: e.name,
    rxcui: e.rxcui,
    genericRxcui: e.genericRxcui,
    ingredientRxcuis: _decodeStackStringList(e.ingredientRxcuisCol),
    drugClassIds: _decodeStackStringList(e.drugClassesCol),
  );
}

final depletionReportProvider = FutureProvider<MedNutrientReport>((ref) async {
  final stack = await ref.watch(activeStackProvider.future);
  final medications = stack
      .where((e) => e.type == 'medication')
      .map(_depletionIdentityFor)
      .toList(growable: false);

  if (medications.isEmpty) {
    return (
      status: MedNutrientLoadStatus.loaded,
      matches: const <DepletionMatch>[],
    );
  }

  final repo = ref.watch(reference_data.referenceDataRepositoryProvider);
  final load = await repo.loadMedicationDepletions();
  if (load.status == MedNutrientLoadStatus.unavailable) {
    // The clinical asset could not be activated. Surface UNAVAILABLE, never an
    // empty "no depletions" result that reads as an all-clear.
    return (
      status: MedNutrientLoadStatus.unavailable,
      matches: const <DepletionMatch>[],
    );
  }
  final depletionsData = load.data;

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
  return (
    status: load.status,
    matches: checker.check(
      medications: const [],
      medicationIdentities: medications,
      depletionsData: depletionsData,
      stackCanonicalIds: coveredIds,
      stackDoses: stackDoses,
    ),
  );
});

/// Curated watch thresholds evaluated against how long each medication has
/// actually been tracked, keyed by depletion entry id.
///
/// Empty whenever the clinical asset is unavailable or no reviewer has authored
/// a `watch_threshold_days`. That is the current state of every entry, so this
/// provider is inert until curated data enables it — it can never manufacture a
/// clinical timeline on its own.
final depletionWatchProvider =
    FutureProvider<Map<String, DepletionWatchStatus>>((ref) async {
      final stack = await ref.watch(activeStackProvider.future);
      final medications = <WatchedMedication>[
        for (final e in stack)
          if (e.type == 'medication')
            (stackEntryId: e.id, identity: _depletionIdentityFor(e)),
      ];
      if (medications.isEmpty) return const {};

      final load = await ref
          .watch(reference_data.referenceDataRepositoryProvider)
          .loadMedicationDepletions();
      if (load.status == MedNutrientLoadStatus.unavailable) {
        // Never annotate a card the checker could not build. An unavailable
        // asset is not a "nothing due" answer.
        return const {};
      }

      // Precedence, most to least truthful:
      //   1. `started_at` — what the person reports. Someone on metformin
      //      since 2019 who installed last week is only visible this way.
      //   2. the append-only event log, which distinguishes an Undo from a
      //      genuine stop-and-restart.
      //   3. `added_at`, for rows predating the v10 log.
      // Each is a fact the app was told or observed; none is inferred.
      final logged = await ref
          .read(healthEventRepositoryProvider)
          .getStackTrackedSince();
      final trackedSince = <String, DateTime>{};
      for (final e in stack) {
        if (e.type != 'medication') continue;
        final reported = e.startedAt;
        if (reported != null) {
          trackedSince[e.id] = reported.toUtc();
          continue;
        }
        trackedSince[e.id] = (logged[e.id] ?? e.addedAt).toUtc();
      }

      return DepletionWatchResolver().evaluate(
        medications: medications,
        depletionsData: load.data,
        trackedSinceByStackEntry: trackedSince,
        now: DateTime.now(),
      );
    });

/// Drug-class ids resolved for the user's CURRENT-STACK medications — the
/// same current class bridge stack safety and depletion consume. Stored
/// identity and runtime classes are resolved against the current bundled map
/// so membership corrections and exclusions also reach older stack entries.
/// Product detail then gates pipeline-authored warnings on actual medications.
final currentStackMedicationClassIdsProvider = FutureProvider<Set<String>>((
  ref,
) async {
  final stack = await ref.watch(activeStackProvider.future);
  final classIds = <String>[];
  MedicationClassBridge? bridge;
  for (final e in stack) {
    if (e.type != 'medication') continue;
    bridge ??= MedicationClassBridge(
      db: ref.watch(interactionDatabaseProvider),
    );
    final snapshot = MedicationIdentitySnapshot.fromStackRow(e);
    final resolution = await bridge.resolve(
      selectedRxcui: snapshot.rxcui,
      genericRxcui: snapshot.genericRxcui,
      ingredientRxcuis: snapshot.ingredientRxcuis,
      runtimeClassIds: snapshot.drugClassIds,
    );
    classIds.addAll(resolution.mergedInteractionClassIds);
  }
  // Stack rows store the `class:*` interaction-bridge vocab
  // (mergedInteractionClassIds); the profile gate matches the profile vocab.
  // Crosswalk via the single bridge contract (fail-open, verified-seed-only).
  return MedicationClassBridge.profileGateIdsForClasses(classIds).toSet();
});

/// The classes the stack rows themselves record, for a screen that still has
/// catalog warnings to match when [currentStackMedicationClassIdsProvider] has
/// failed, as it does while the rules file is withheld. Screens keep reporting
/// that failure; this only stops an unrelated warning from disappearing.
Set<String> storedStackMedicationClassIds(
  Iterable<UserStacksLocalData> stack,
) => MedicationClassBridge.profileGateIdsForClasses(
  stack
      .where((e) => e.type == 'medication')
      .expand((e) => MedicationIdentitySnapshot.fromStackRow(e).drugClassIds),
).toSet();

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
