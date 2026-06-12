// Stack safety aggregations: the pre-add check, the aggregated banner
// report, recalled ingredients, and medication depletion matches.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/core/scoring/coverage.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_provider_helpers.dart';
import 'package:pharmaguide/services/health/product_health_facts.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_aggregator.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/timing_evaluation_service.dart';

/// Runs [StackInteractionChecker] for the candidate product against the
/// current stack. Returns an empty list when the stack is empty or when
/// the product has no flags that could trigger a warning.
///
/// This runs off the bundled core DB only — no network. It's fast enough
/// to await inside a "Verifying safety…" confirmation step.
final safetyCheckForAddProvider = FutureProvider.family
    .autoDispose<List<InteractionResult>, String>((ref, dsldId) async {
      final coreDb = ref.watch(coreDatabaseProvider);
      final userDb = ref.watch(userDatabaseProvider);

      final candidate = await coreDb.findById(dsldId);
      if (candidate == null) return const [];

      final stack = await userDb.getActiveStack();
      if (stack.isEmpty) return const [];

      // Pair each stack entry with its core product row (skip items missing a
      // dsldId — those are hand-entered medications that don't have a fingerprint).
      final stackProducts = <ProductsCoreData>[];
      for (final entry in stack) {
        final id = entry.dsldId;
        if (id == null || id.isEmpty) continue;
        try {
          final product = await coreDb.findById(id);
          if (product != null) stackProducts.add(product);
        } on Exception {
          // Skip broken entries — we're best-effort here.
        }
      }

      if (stackProducts.isEmpty) return const [];

      final newFp = parseFingerprint(candidate.ingredientFingerprint);
      final stackFps = stackProducts
          .map((p) => parseFingerprint(p.ingredientFingerprint))
          .toList(growable: false);

      bool flag(int? v) => v == 1;

      return StackInteractionChecker().checkSafety(
        newProductFingerprint: newFp,
        stackFingerprints: stackFps,
        newContainsStimulants: flag(candidate.containsStimulants),
        newContainsSedatives: flag(candidate.containsSedatives),
        newContainsBloodThinners: flag(candidate.containsBloodThinners),
        stackContainsStimulants: stackProducts
            .map((p) => flag(p.containsStimulants))
            .toList(),
        stackContainsSedatives: stackProducts
            .map((p) => flag(p.containsSedatives))
            .toList(),
        stackContainsBloodThinners: stackProducts
            .map((p) => flag(p.containsBloodThinners))
            .toList(),
        stackProductNames: stackProducts
            .map((p) => p.productName)
            .toList(growable: false),
        newProductName: candidate.productName,
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

  // Take a dependency on the active stack so any mutation invalidates us.
  final stack = await ref.watch(activeStackProvider.future);
  if (stack.isEmpty) return const StackSafetyReport();

  // Nutrient statuses feed into the report as-is — the report's
  // `isEmpty` / `overallSeverity` getters already filter sub-warn tiers.
  // If the nutrient provider errors, we still want the interaction half
  // of the report to render, so we fall back to an empty list.
  List<NutrientStatus> nutrientStatuses;
  try {
    nutrientStatuses = await ref.watch(stackNutrientStatusesProvider.future);
  } on Object {
    nutrientStatuses = const <NutrientStatus>[];
  }

  final supplements = stack
      .where((e) => e.type == 'supplement')
      .toList(growable: false);
  final medications = stack
      .where((e) => e.type == 'medication')
      .toList(growable: false);

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
      } on Object {
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
  if (hydrated.isNotEmpty && medications.isNotEmpty) {
    for (final self in hydrated) {
      final canonicalIds = canonicalIdsForProduct(self.product);
      if (canonicalIds.isEmpty) continue;
      List<InteractionResult> hits;
      try {
        hits = await checker.checkMedicationInteractions(
          newProductCanonicalIds: canonicalIds,
          stackMedications: medications,
          db: interactionDb,
          newProductName: self.entry.name,
        );
      } on Object {
        continue;
      }
      for (final r in hits) {
        if (seenMedIds.add(r.id)) medicationInteractions.add(r);
      }
    }
  }
  if (medications.isNotEmpty) {
    try {
      final hits = await checker.checkMedicationFoodAdvisories(
        stackMedications: medications,
        db: interactionDb,
      );
      for (final r in hits) {
        if (seenMedIds.add(r.id)) medicationInteractions.add(r);
      }
    } on Object {
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
      } on Object {
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
  if (medications.length >= 2) {
    for (var i = 0; i < medications.length; i++) {
      final self = [medications[i]];
      final others = [
        for (var j = 0; j < medications.length; j++)
          if (j != i) medications[j],
      ];
      List<InteractionResult> hits;
      try {
        hits = await checker.checkMedicationPairInteractions(
          newMedications: self,
          existingMedications: others,
          db: interactionDb,
        );
      } on Object {
        continue;
      }
      for (final r in hits) {
        if (seenMedPairIds.add(r.id)) medicationPairInteractions.add(r);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 5. Timing optimization evaluation.
  //    Cross-reference the stack's ingredient tags and medication names
  //    against timing_rules.json to produce actionable timing advice.
  // ---------------------------------------------------------------------------
  List<TimingOptimization> timingOptimizations = const <TimingOptimization>[];
  try {
    final refDataRepo = ReferenceDataRepository();
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
    final medicationNames = medications
        .map((m) => m.name)
        .toList(growable: false);

    timingOptimizations = timingService.evaluateStack(
      supplementTags: supplementTags,
      medicationNames: medicationNames,
    );
  } on Object {
    // Timing is advisory — never let it crash the safety report.
    timingOptimizations = const <TimingOptimization>[];
  }

  return StackSafetyReport(
    nutrientStatuses: nutrientStatuses,
    stackInteractions: stackInteractions,
    medicationInteractions: medicationInteractions,
    medicationPairInteractions: medicationPairInteractions,
    categoryWarnings: categoryWarnings,
    timingOptimizations: timingOptimizations,
    coverageIncomplete: coverageIncomplete,
  );
});

/// Recall detection: finds products in the user's stack that contain banned
/// or recalled ingredients, returning a [RecalledIngredientsReport] with
/// violations sorted by severity.
final recalledIngredientsReportProvider = FutureProvider<RecalledIngredientsReport>((
  ref,
) async {
  final coreDb = ref.watch(coreDatabaseProvider);
  // Read the repo via the provider so tests can override the asset source.
  // Sprint 27.6 added this indirection to enable integration tests of
  // the scan→flag path without needing to bundle fixture assets.
  final refDataRepo = ref.watch(referenceDataRepositoryProvider);

  // Take a dependency on the active stack so any mutation invalidates us.
  final stack = await ref.watch(activeStackProvider.future);
  if (stack.isEmpty) return RecalledIngredientsReport.empty();

  final supplements = stack
      .where((e) => e.type == 'supplement')
      .toList(growable: false);
  if (supplements.isEmpty) return RecalledIngredientsReport.empty();

  // Load banned/recalled ingredients data.
  final Map<String, dynamic> recallData;
  try {
    recallData = await refDataRepo.loadBannedRecalledIngredients();
  } on Object {
    return RecalledIngredientsReport.empty();
  }

  final recalledRaw = recallData['recalled_ingredients'];
  final recalledList = recalledRaw is List ? recalledRaw : null;
  if (recalledList == null || recalledList.isEmpty) {
    return RecalledIngredientsReport.empty();
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

  return RecalledIngredientsReport(violations: violations);
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

  final repo = ref.watch(referenceDataRepositoryProvider);
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
