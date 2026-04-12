// Riverpod providers for Sprint 5a Stack wiring.
//
// What lives here:
// - [activeStackProvider] — FutureProvider exposing the user's current
//   active stack (soft-deletes excluded, newest first).
// - [stackEntryForDsldIdProvider] — FutureProvider.family so any widget
//   can ask "is this product already in the stack?" without re-fetching
//   the whole stack.
// - [safetyCheckForAddProvider] — FutureProvider.family that runs the
//   existing StackInteractionChecker against the current stack + the
//   candidate product, returning a list of [InteractionResult]. The UI
//   shows these in the pre-add confirmation sheet (Sprint 5b UI wiring).
// - [stackSafetyReportProvider] — FutureProvider that aggregates every
//   safety signal (M1 nutrient statuses + M4 curated supplement pair and
//   medication interactions + legacy category heuristics) into a single
//   [StackSafetyReport] the banner renders. Rebuilds whenever the stack
//   or nutrient statuses change. M4 §8.3.
// - [stackActionsProvider] — Provider exposing a [StackActions] service
//   with imperative `add` / `remove` / `restore` methods. After every
//   mutation, all dependent providers are invalidated so the UI updates
//   within a frame.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/features/stack/providers/stack_nutrient_providers.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';
import 'package:pharmaguide/services/stack/recalled_ingredient_result.dart';
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';
import 'package:pharmaguide/services/stack/stack_nutrient_models.dart';
import 'package:pharmaguide/services/stack/stack_safety_report.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

/// All non-deleted stack entries, newest first.
final activeStackProvider = FutureProvider<List<UserStacksLocalData>>((ref) {
  final userDb = ref.watch(userDatabaseProvider);
  return userDb.getActiveStack();
});

/// Returns the active (non-deleted) stack entry for a given product, or
/// null if the user has not added that product. Used by product detail
/// screens to toggle between Add-to-Stack / In-Stack states.
///
/// This re-fetches on every call rather than filtering [activeStackProvider]
/// because it's used in a different part of the tree and we want it
/// separately keyed for rebuild isolation.
final stackEntryForDsldIdProvider = FutureProvider.family
    .autoDispose<UserStacksLocalData?, String>((ref, dsldId) async {
  // Take a dependency on the active stack so mutations propagate.
  await ref.watch(activeStackProvider.future);
  final userDb = ref.watch(userDatabaseProvider);
  return userDb.findStackEntryByDsldId(dsldId);
});

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

  // Build the fingerprint inputs for the checker.
  Map<String, dynamic> parseFingerprint(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // Silently fall through.
    }
    return const {};
  }

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
    stackContainsStimulants:
        stackProducts.map((p) => flag(p.containsStimulants)).toList(),
    stackContainsSedatives:
        stackProducts.map((p) => flag(p.containsSedatives)).toList(),
    stackContainsBloodThinners:
        stackProducts.map((p) => flag(p.containsBloodThinners)).toList(),
    stackProductNames:
        stackProducts.map((p) => p.productName).toList(growable: false),
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
final stackSafetyReportProvider =
    FutureProvider<StackSafetyReport>((ref) async {
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
    nutrientStatuses =
        await ref.watch(stackNutrientStatusesProvider.future);
  } on Object {
    nutrientStatuses = const <NutrientStatus>[];
  }

  final supplements =
      stack.where((e) => e.type == 'supplement').toList(growable: false);
  final medications =
      stack.where((e) => e.type == 'medication').toList(growable: false);

  // Hydrate each supplement once — we need the core row for fingerprints
  // (category heuristics) and the ingredient_keys JSON for canonical ids.
  final hydrated = <_HydratedSupplement>[];
  for (final entry in supplements) {
    final id = entry.dsldId;
    if (id == null || id.isEmpty) continue;
    ProductsCoreData? product;
    try {
      product = await coreDb.findById(id);
    } on Exception {
      continue;
    }
    if (product == null) continue;
    hydrated.add(_HydratedSupplement(entry: entry, product: product));
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
      final canonicalIds = _canonicalIdsForProduct(self.product);
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
      final canonicalIds = _canonicalIdsForProduct(self.product);
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
      final newFp = _parseFingerprint(self.product.ingredientFingerprint);
      final stackFps = others
          .map((o) => _parseFingerprint(o.product.ingredientFingerprint))
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
        final key = _symmetricKey(r.agent1Name, r.agent2Name, r.id);
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

  return StackSafetyReport(
    nutrientStatuses: nutrientStatuses,
    stackInteractions: stackInteractions,
    medicationInteractions: medicationInteractions,
    medicationPairInteractions: medicationPairInteractions,
    categoryWarnings: categoryWarnings,
  );
});

/// Synergy detection: finds ingredient clusters in the user's stack and
/// returns a [SynergyReport] with matching clusters sorted by evidence tier.
final synergyReportProvider = FutureProvider<SynergyReport>((ref) async {
  final coreDb = ref.watch(coreDatabaseProvider);
  final refDataRepo = ReferenceDataRepository();

  // Take a dependency on the active stack so any mutation invalidates us.
  final stack = await ref.watch(activeStackProvider.future);
  if (stack.isEmpty) return SynergyReport.empty();

  final supplements =
      stack.where((e) => e.type == 'supplement').toList(growable: false);
  if (supplements.isEmpty) return SynergyReport.empty();

  // Hydrate each supplement to get ingredient fingerprints.
  final hydrated = <_HydratedSupplement>[];
  for (final entry in supplements) {
    final id = entry.dsldId;
    if (id == null || id.isEmpty) continue;
    ProductsCoreData? product;
    try {
      product = await coreDb.findById(id);
    } on Exception {
      continue;
    }
    if (product == null) continue;
    hydrated.add(_HydratedSupplement(entry: entry, product: product));
  }

  if (hydrated.isEmpty) return SynergyReport.empty();

  // Extract canonical ids from all supplements.
  final stackCanonicalIds = <String>{};
  for (final h in hydrated) {
    final ids = _canonicalIdsForProduct(h.product);
    stackCanonicalIds.addAll(ids);
  }

  if (stackCanonicalIds.isEmpty) return SynergyReport.empty();

  // Load synergy clusters and find matches.
  late Map<String, dynamic> clustersData;
  try {
    clustersData = await refDataRepo.loadSynergyClusters();
  } on Object {
    return SynergyReport.empty();
  }

  final clustersList = clustersData['clusters'] as List<dynamic>?;
  if (clustersList == null || clustersList.isEmpty) {
    return SynergyReport.empty();
  }

  final matches = <SynergyMatch>[];
  int totalBonus = 0;

  for (final clusterJson in clustersList) {
    final cluster = clusterJson as Map<String, dynamic>;
    final clusterId = cluster['cluster_id'] as String?;
    final name = cluster['name'] as String?;
    final ingredients = (cluster['ingredients'] as List<dynamic>?)
            ?.map((i) => i.toString())
            .toList() ??
        const <String>[];
    final mechanism = cluster['mechanism'] as String?;
    final bonusPoints = cluster['bonus_points'] as int? ?? 0;
    final evidenceTier = cluster['evidence_tier'] as String? ?? 'limited';
    final citations =
        (cluster['citations'] as List<dynamic>?)?.map((c) => c.toString()).toList() ??
            const <String>[];

    // Check if all ingredients in the cluster are in the stack.
    final allPresent = ingredients.every((ing) => stackCanonicalIds.contains(ing));
    if (allPresent && clusterId != null && name != null && mechanism != null) {
      matches.add(
        SynergyMatch(
          clusterId: clusterId,
          clusterName: name,
          matchedIngredients: ingredients,
          mechanism: mechanism,
          bonusPoints: bonusPoints,
          evidenceTier: evidenceTier,
          citations: citations,
        ),
      );
      totalBonus += bonusPoints;
    }
  }

  return SynergyReport(
    matches: matches,
    totalBonusPoints: totalBonus,
    isEmpty: matches.isEmpty,
  );
});

/// Recall detection: finds products in the user's stack that contain banned
/// or recalled ingredients, returning a [RecalledIngredientsReport] with
/// violations sorted by severity.
final recalledIngredientsReportProvider =
    FutureProvider<RecalledIngredientsReport>((ref) async {
  final coreDb = ref.watch(coreDatabaseProvider);
  final refDataRepo = ReferenceDataRepository();

  // Take a dependency on the active stack so any mutation invalidates us.
  final stack = await ref.watch(activeStackProvider.future);
  if (stack.isEmpty) return RecalledIngredientsReport.empty();

  final supplements =
      stack.where((e) => e.type == 'supplement').toList(growable: false);
  if (supplements.isEmpty) return RecalledIngredientsReport.empty();

  // Load banned/recalled ingredients data.
  late Map<String, dynamic> recallData;
  try {
    recallData = await refDataRepo.loadBannedRecalledIngredients();
  } on Object {
    return RecalledIngredientsReport.empty();
  }

  final recalledList = recallData['recalled_ingredients'] as List<dynamic>?;
  if (recalledList == null || recalledList.isEmpty) {
    return RecalledIngredientsReport.empty();
  }

  // Build a map of canonical_id → RecalledIngredientAlert for fast lookup.
  final recalledMap = <String, RecalledIngredientAlert>{};
  for (final recallJson in recalledList) {
    final recall = recallJson as Map<String, dynamic>;
    final canonicalId = recall['canonical_id'] as String?;
    if (canonicalId == null) continue;

    final commonNames = (recall['common_names'] as List<dynamic>?)
            ?.map((c) => c.toString())
            .toList() ??
        const <String>[];
    final recallStatus = recall['recall_status'] as String? ?? 'warning';
    final regulatoryBasis = recall['regulatory_basis'] as String? ?? '';
    final reason = recall['reason'] as String? ?? '';
    final effectiveDate = recall['effective_date'] as String? ?? '';
    final warningMessage = recall['warning_message'] as String? ?? '';
    final severity = recall['severity'] as String? ?? 'major';

    recalledMap[canonicalId] = RecalledIngredientAlert(
      canonicalId: canonicalId,
      commonNames: commonNames,
      recallStatus: recallStatus,
      regulatoryBasis: regulatoryBasis,
      reason: reason,
      effectiveDate: effectiveDate,
      warningMessage: warningMessage,
      severity: severity,
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
    final canonicalIds = _canonicalIdsForProduct(product);
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

  return RecalledIngredientsReport(
    violations: violations,
    isEmpty: violations.isEmpty,
  );
});

class _HydratedSupplement {
  const _HydratedSupplement({required this.entry, required this.product});
  final UserStacksLocalData entry;
  final ProductsCoreData product;
}

/// Decode a `products_core.ingredient_fingerprint` blob into a list of
/// canonical ingredient ids. The pipeline writes a map of
/// `canonical_id → {...}`; we just need the keys. Broken JSON degrades
/// to an empty list.
List<String> _canonicalIdsForProduct(ProductsCoreData product) {
  final raw = product.ingredientFingerprint;
  if (raw == null || raw.isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.keys
          .map((k) => k.toString().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
  } on FormatException {
    return const <String>[];
  }
  return const <String>[];
}

Map<String, dynamic> _parseFingerprint(String? raw) {
  if (raw == null || raw.isEmpty) return const <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return const <String, dynamic>{};
  }
  return const <String, dynamic>{};
}

/// Stable key for a heuristic interaction between two agents — ignores
/// ordering so we dedupe A×B and B×A to one warning per category.
String _symmetricKey(String a, String b, String ruleId) {
  // Keep the rule prefix (`STACK_STIM_SED`, `STACK_SED_STIM`,
  // `STACK_BLOOD_THINNER_*`, ...) but strip the trailing numeric index
  // so A→B and B→A collapse to the same bucket.
  final prefix = ruleId.replaceAll(RegExp(r'_\d+$'), '');
  final pair = (a.compareTo(b) <= 0) ? '$a|$b' : '$b|$a';
  return '$prefix#$pair';
}

/// Imperative stack actions (add / remove / restore). Never call directly
/// from a build method — invoke from an onTap or an async user event.
class StackActions {
  final Ref _ref;
  StackActions(this._ref);

  /// Generate a reasonably unique local id. We don't have the `uuid`
  /// package in pubspec, and since stack ids are scoped to a single device
  /// (server assigns its own id on sync), `dsldId + microseconds` is
  /// collision-proof for all realistic uses.
  String _newId(String? dsldId) {
    final base = dsldId ?? 'manual';
    return '${base}_${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Add a product to the stack. Returns the new entry's id so the caller
  /// can show an undo snackbar that references it.
  Future<String> addProduct(ProductsCoreData product) async {
    final userDb = _ref.read(userDatabaseProvider);
    final id = _newId(product.dsldId);
    await userDb.addToStack(
      UserStacksLocalCompanion(
        id: Value(id),
        type: const Value('supplement'),
        name: Value(product.productName),
        dsldId: Value(product.dsldId),
        ingredientKeys: Value(product.ingredientFingerprint),
      ),
    );
    _invalidate();
    _triggerSync();
    return id;
  }

  /// Add a medication to the stack (M4 §8.5).
  ///
  /// Medications are PHI: they get `type='medication'` so the Supabase
  /// sync layer can refuse to push them. The privacy grep test
  /// (`test/release_gate/phi_medication_no_sync_test.dart`) build-fails
  /// if any sync code path touches a `'medication'` row.
  ///
  /// [rxcui] is the NLM RxNorm concept id (string) — present when the
  /// user picked a specific drug from the autocomplete; null when they
  /// fell back to the offline class picker (`drugClasses` is set
  /// instead).
  ///
  /// [drugClasses] is the list of `class:*` ids the medication belongs
  /// to, JSON-encoded into the `drug_classes` column. Either [rxcui] or
  /// at least one entry in [drugClasses] must be non-empty so the
  /// curated interaction lookup has something to match on.
  ///
  /// We deliberately do NOT call [_triggerSync] for medications — the
  /// sync layer would skip them anyway, but skipping the call entirely
  /// makes the no-sync contract obvious in code review.
  Future<String> addMedication({
    required String name,
    String? rxcui,
    List<String> drugClasses = const <String>[],
    String? dosage,
    String? frequency,
  }) async {
    assert(
      (rxcui != null && rxcui.isNotEmpty) || drugClasses.isNotEmpty,
      'medication needs at least one of rxcui or drugClasses to participate '
      'in interaction checks',
    );

    final userDb = _ref.read(userDatabaseProvider);
    final id = _newId(rxcui != null ? 'rx_$rxcui' : 'med');
    final classesJson =
        drugClasses.isEmpty ? null : jsonEncode(drugClasses);

    await userDb.addToStack(
      UserStacksLocalCompanion(
        id: Value(id),
        type: const Value('medication'),
        name: Value(name),
        rxcui: Value(rxcui),
        drugClassesCol: Value(classesJson),
        dosage: Value(dosage),
        frequency: Value(frequency),
      ),
    );
    _invalidate();
    // Intentionally NOT calling _triggerSync — medications never leave
    // the device. See spec §8.5.
    return id;
  }

  /// Soft-delete a stack entry (sets `deletedAt`).
  Future<void> remove(String entryId) async {
    final userDb = _ref.read(userDatabaseProvider);
    await userDb.removeFromStack(entryId);
    _invalidate();
    _triggerSync();
  }

  /// Reverse a soft-delete — clears `deletedAt` so the entry re-appears.
  /// Used to implement "Undo" on the remove snackbar.
  Future<void> restore(String entryId) async {
    final userDb = _ref.read(userDatabaseProvider);
    await (userDb.update(userDb.userStacksLocal)
          ..where((t) => t.id.equals(entryId)))
        .write(
      UserStacksLocalCompanion(
        deletedAt: const Value(null),
        clientUpdatedAt: Value(DateTime.now()),
      ),
    );
    _invalidate();
    _triggerSync();
  }

  void _invalidate() {
    _ref.invalidate(activeStackProvider);
    // Family providers invalidate per-key when the root is invalidated;
    // force a broad invalidate so every currently-listening detail screen
    // rebuilds its "in stack?" state.
    _ref.invalidate(stackEntryForDsldIdProvider);
    _ref.invalidate(safetyCheckForAddProvider);
    // The aggregated banner report re-runs on every mutation so the
    // top-of-stack banner updates in the same frame as the product
    // list. activeStackProvider is already listed above, but we spell
    // this out explicitly so a future refactor that drops the stack
    // dependency can't accidentally freeze the banner.
    _ref.invalidate(stackSafetyReportProvider);
    // Synergy and recall detection also depend on the active stack, so they
    // must rebuild whenever the stack changes.
    _ref.invalidate(synergyReportProvider);
    _ref.invalidate(recalledIngredientsReportProvider);
  }

  /// Fire-and-forget sync attempt after every mutation. Silently skips
  /// when offline / guest — the [stackSyncListenerProvider] will catch up
  /// later when the user signs in or connectivity returns.
  void _triggerSync() {
    final service = _ref.read(stackSyncServiceProvider);
    unawaited(service.pushAll());
    _ref.invalidate(pendingSyncCountProvider);
  }
}

final stackActionsProvider = Provider<StackActions>((ref) {
  return StackActions(ref);
});
