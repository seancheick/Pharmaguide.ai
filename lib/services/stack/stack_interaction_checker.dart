import 'dart:convert';

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/utils/product_canonical_ids.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';

/// Checks safety when adding a new product to the supplement stack.
///
/// Two layers of checks live here:
///
///   1. **Heuristic category checks** ([checkSafety]) — operate on
///      product fingerprints from `products_core` (stim/sed antagonism,
///      blood-thinner stacking, duplicate active ingredients). No DB
///      lookup; offline by construction.
///   2. **Curated DB lookups** ([checkSupplementPairInteractions],
///      [checkMedicationInteractions]) — query the bundled M2 interaction
///      DB for pre-verified rows pairing a new product's canonical
///      ingredient ids against the existing stack. Each hit is mapped to
///      [InteractionResult.fromRow] with `InteractionSource.pipeline`.
///
/// All curated lookups dedupe by row id so a product whose ingredients
/// all collide with the same curated row only surfaces once. The
/// retired-row filter is enforced at the DB layer (spec §7.3) so callers
/// here never need to re-apply it.
class StackInteractionChecker {
  /// Run all safety checks for adding newProduct to existing stack.
  List<InteractionResult> checkSafety({
    required Map<String, dynamic> newProductFingerprint,
    required List<Map<String, dynamic>> stackFingerprints,
    required bool newContainsStimulants,
    required bool newContainsSedatives,
    required bool newContainsBloodThinners,
    required List<bool> stackContainsStimulants,
    required List<bool> stackContainsSedatives,
    required List<bool> stackContainsBloodThinners,
    required List<String> stackProductNames,
    required String newProductName,
  }) {
    final results = <InteractionResult>[];

    // Check 1: Stimulant/sedative antagonism
    if (newContainsStimulants) {
      for (int i = 0; i < stackContainsSedatives.length; i++) {
        if (stackContainsSedatives[i]) {
          results.add(
            InteractionResult(
              id: 'STACK_STIM_SED_$i',
              type: InteractionType.supplementSupplement,
              severity: Severity.caution,
              evidenceLevel: EvidenceLevel.established,
              agent1Name: newProductName,
              agent2Name: stackProductNames[i],
              mechanism:
                  'Stack contains both stimulants and sedatives — opposing effects may reduce effectiveness of both',
              management:
                  'Consider taking at different times or choosing one over the other',
              doseDependant: false,
              doseThreshold: null,
              sourceUrls: [],
              source: InteractionSource.stackEngine,
            ),
          );
        }
      }
    }
    if (newContainsSedatives) {
      for (int i = 0; i < stackContainsStimulants.length; i++) {
        if (stackContainsStimulants[i]) {
          results.add(
            InteractionResult(
              id: 'STACK_SED_STIM_$i',
              type: InteractionType.supplementSupplement,
              severity: Severity.caution,
              evidenceLevel: EvidenceLevel.established,
              agent1Name: newProductName,
              agent2Name: stackProductNames[i],
              mechanism:
                  'Stack contains both sedatives and stimulants — opposing effects',
              management: 'Consider separating by time of day',
              doseDependant: false,
              doseThreshold: null,
              sourceUrls: [],
              source: InteractionSource.stackEngine,
            ),
          );
        }
      }
    }

    // Check 2: Blood thinner stacking
    if (newContainsBloodThinners) {
      for (int i = 0; i < stackContainsBloodThinners.length; i++) {
        if (stackContainsBloodThinners[i]) {
          results.add(
            InteractionResult(
              id: 'STACK_BT_$i',
              type: InteractionType.supplementSupplement,
              severity: Severity.avoid,
              evidenceLevel: EvidenceLevel.established,
              agent1Name: newProductName,
              agent2Name: stackProductNames[i],
              mechanism:
                  'Multiple blood-thinning supplements increase bleeding risk',
              management:
                  'Consult healthcare provider before combining blood-thinning supplements',
              doseDependant: true,
              doseThreshold: null,
              sourceUrls: [],
              source: InteractionSource.stackEngine,
            ),
          );
        }
      }
    }

    // Check 3: Duplicate active ingredients
    final newNutrients =
        (newProductFingerprint['nutrients'] as Map?)?.keys.toSet() ?? {};
    for (int i = 0; i < stackFingerprints.length; i++) {
      final stackNutrients =
          (stackFingerprints[i]['nutrients'] as Map?)?.keys.toSet() ?? {};
      final overlap = newNutrients.intersection(stackNutrients);
      if (overlap.length >= 3) {
        results.add(
          InteractionResult(
            id: 'STACK_DUP_$i',
            type: InteractionType.supplementSupplement,
            severity: Severity.monitor,
            evidenceLevel: EvidenceLevel.probable,
            agent1Name: newProductName,
            agent2Name: stackProductNames[i],
            mechanism:
                '${overlap.length} overlapping nutrients: ${overlap.take(3).join(", ")}${overlap.length > 3 ? "..." : ""}',
            management: 'Check cumulative doses against daily upper limits',
            doseDependant: true,
            doseThreshold: null,
            sourceUrls: [],
            source: InteractionSource.stackEngine,
          ),
        );
      }
    }

    return results;
  }

  /// Check a new product's canonical ingredient ids against every OTHER
  /// supplement already in the user's stack via the curated interaction
  /// DB (spec §8.2).
  ///
  /// **Inputs**
  ///
  /// - [newProductCanonicalIds] — canonical ids for the new product's
  ///   mapped ingredients (same shape `stack_nutrient_aggregator`
  ///   reads). Lowercased + trimmed defensively. Empty list ⇒ no-op.
  /// - [stackSupplements] — every existing stack row where
  ///   `type='supplement'`. The caller is responsible for filtering by
  ///   type and excluding the new product itself if it is being
  ///   re-added.
  /// - [db] — bundled [InteractionDatabase].
  ///
  /// **Lookup strategy**
  ///
  /// We call [InteractionDatabase.lookupByCanonicalId] once per new
  /// canonical id (which queries the `agent1_canonical_id` /
  /// `agent2_canonical_id` columns directly), then filter the
  /// returned rows in memory by checking that the OTHER side's
  /// canonical id is one the user's stack carries. This avoids
  /// `lookupPair` because that helper joins on the raw `agent_id`
  /// column (which for supplements stores the UMLS CUI, not the
  /// lowercased canonical string).
  ///
  /// **Output**
  ///
  /// One [InteractionResult] per unique curated row that pairs a new
  /// canonical id with a stack canonical id. Results are mapped via
  /// [InteractionResult.fromRow] and tagged
  /// [InteractionSource.pipeline] — the data is curated, even though
  /// the join happens at runtime. Agent-name overrides put the new
  /// product's name on agent1 and the matching stack supplement's
  /// name on agent2 regardless of which slot the pipeline stored them
  /// in.
  ///
  /// **Dedup contract**
  ///
  /// We dedupe by `row.id` so the user sees a single warning even
  /// when the same row is reachable via multiple canonical ids on the
  /// new product or multiple stack rows.
  ///
  /// **Error handling**
  ///
  /// Per-row JSON decode errors on stack rows are swallowed — that one
  /// stack entry contributes nothing rather than aborting the call.
  /// The method returns an empty list on a wholly empty input pair,
  /// never throws.
  Future<List<InteractionResult>> checkSupplementPairInteractions({
    required List<String> newProductCanonicalIds,
    required List<UserStacksLocalData> stackSupplements,
    required InteractionDatabase db,
    String newProductName = 'New product',
  }) async {
    if (newProductCanonicalIds.isEmpty || stackSupplements.isEmpty) {
      return const <InteractionResult>[];
    }

    final newIds = _normalizeCanonicalIds(newProductCanonicalIds);
    if (newIds.isEmpty) return const <InteractionResult>[];
    final newIdSet = newIds.toSet();

    // Build canonical_id → display name lookup for the stack so we can
    // attach the matching supplement's user-facing name to each result.
    final stackIdToName = <String, String>{};
    for (final entry in stackSupplements) {
      for (final cid in _canonicalIdsFor(entry)) {
        stackIdToName.putIfAbsent(cid, () => entry.name);
      }
    }
    if (stackIdToName.isEmpty) return const <InteractionResult>[];

    final results = <InteractionResult>[];
    final seenRowIds = <String>{};

    for (final newId in newIds) {
      final rows = await db.lookupByCanonicalId(newId);
      for (final row in rows) {
        if (seenRowIds.contains(row.id)) continue;

        final otherCid = _otherCanonicalId(row, newId);
        if (otherCid == null) continue;

        // The other side must be a supplement the user has in their
        // stack. If the other side is also one of the new product's
        // own canonical ids, that's a within-product pair, not a
        // stack pair — skip unless the stack ALSO carries it.
        if (newIdSet.contains(otherCid) &&
            !stackIdToName.containsKey(otherCid)) {
          continue;
        }
        final stackName = stackIdToName[otherCid];
        if (stackName == null) continue;

        seenRowIds.add(row.id);
        results.add(
          InteractionResult.fromRow(
            row,
            source: InteractionSource.pipeline,
            agent1NameOverride: newProductName,
            agent2NameOverride: stackName,
          ),
        );
      }
    }

    return results;
  }

  /// Check a new product's canonical ingredient ids against every
  /// medication in the user's stack (spec §8.2).
  ///
  /// **Medication identity** is read off the [UserStacksLocalData] row
  /// in two shapes:
  ///
  ///   1. `rxcui` — single drug (NLM RxNorm concept id). The check
  ///      matches curated rows where the OTHER side has
  ///      `agent_type='drug'` and `agent_id == rxcui`.
  ///   2. `drug_classes` — JSON array of `class:*` ids the medication
  ///      belongs to (populated by `RxNormApiService.getClasses` at
  ///      med-add time). The check matches curated rows where the
  ///      OTHER side has `agent_type='drug_class'` and `agent_id`
  ///      equals one of the medication's classes. This is what makes
  ///      class-level rows like `DDI_ACE_POTASSIUM` fire against any
  ///      specific ACE inhibitor the user added.
  ///
  /// A medication with neither rxcui nor drug_classes contributes
  /// nothing — the M4 G11 wiring guarantees at least one of those is
  /// populated when a med is added. The caller is responsible for
  /// filtering `stackMedications` to `type='medication'` rows.
  ///
  /// **Lookup strategy** mirrors [checkSupplementPairInteractions]:
  /// one [InteractionDatabase.lookupByCanonicalId] call per new
  /// canonical id, then in-memory filtering of the OTHER side. This is
  /// necessary because `lookupPair` joins on raw `agent_id`, not on
  /// `agent_canonical_id`.
  ///
  /// **Dedup** is by `row.id` across the entire call so the same
  /// curated row hit via both an rxcui and one of its parent classes
  /// only surfaces once.
  Future<List<InteractionResult>> checkMedicationInteractions({
    required List<String> newProductCanonicalIds,
    required List<UserStacksLocalData> stackMedications,
    required InteractionDatabase db,
    String newProductName = 'New product',
  }) async {
    if (newProductCanonicalIds.isEmpty || stackMedications.isEmpty) {
      return const <InteractionResult>[];
    }

    final newIds = _normalizeCanonicalIds(newProductCanonicalIds);
    if (newIds.isEmpty) return const <InteractionResult>[];

    // Build (rxcui → med name) and (class → med name) maps so we can
    // identify match candidates and attach the right user-facing name
    // in one pass through the stack.
    final rxcuiToName = <String, String>{};
    final classToName = <String, String>{};
    for (final med in stackMedications) {
      final rxcui = med.rxcui?.trim();
      if (rxcui != null && rxcui.isNotEmpty) {
        rxcuiToName.putIfAbsent(rxcui, () => med.name);
      }
      // Also index the generic IN-level RXCUI so brand picks (Synthroid
      // → 224920) match curated entries keyed on the generic (levothyroxine
      // → 10582). Added 2026-04-14 to fix Bug B3.
      final genericRxcui = med.genericRxcui?.trim();
      if (genericRxcui != null && genericRxcui.isNotEmpty) {
        rxcuiToName.putIfAbsent(genericRxcui, () => med.name);
      }
      // Also index individual ingredient RXCUIs for combination drugs
      // (e.g., Lisinopril/HCTZ → check each ingredient independently).
      for (final ingRxcui in _ingredientRxcuisFor(med)) {
        rxcuiToName.putIfAbsent(ingRxcui, () => med.name);
      }
      for (final cls in _drugClassesFor(med)) {
        classToName.putIfAbsent(cls, () => med.name);
      }
    }
    if (rxcuiToName.isEmpty && classToName.isEmpty) {
      return const <InteractionResult>[];
    }

    final results = <InteractionResult>[];
    final seenRowIds = <String>{};

    for (final newId in newIds) {
      final rows = await db.lookupByCanonicalId(newId);
      for (final row in rows) {
        if (seenRowIds.contains(row.id)) continue;

        // Identify the OTHER side relative to the supplement we just
        // matched on. If newId appears as agent1's canonical, the
        // other side is agent2; otherwise it's agent1.
        final String? otherType;
        final String? otherId;
        if (row.agent1CanonicalId?.toLowerCase() == newId) {
          otherType = row.agent2Type;
          otherId = row.agent2Id;
        } else if (row.agent2CanonicalId?.toLowerCase() == newId) {
          otherType = row.agent1Type;
          otherId = row.agent1Id;
        } else {
          // Should not happen — lookupByCanonicalId returned this
          // row, so one of the two canonical columns must have
          // equalled newId. Defensive only.
          continue;
        }

        String? medName;
        if (otherType == 'drug') {
          medName = rxcuiToName[otherId];
        } else if (otherType == 'drug_class') {
          medName = classToName[otherId];
        }
        if (medName == null) continue;

        seenRowIds.add(row.id);
        results.add(
          InteractionResult.fromRow(
            row,
            source: InteractionSource.pipeline,
            agent1NameOverride: medName,
            agent2NameOverride: newProductName,
          ),
        );
      }
    }

    return results;
  }

  /// Checks medication × medication pair interactions.
  ///
  /// For each medication in [newMedications], fans against every other
  /// medication in [existingMedications] using rxcui and drug_class lookups.
  /// Dedup by row id so the same interaction from both rxcui and class
  /// only surfaces once. Spec §0.2.
  Future<List<InteractionResult>> checkMedicationPairInteractions({
    required List<UserStacksLocalData> newMedications,
    required List<UserStacksLocalData> existingMedications,
    required InteractionDatabase db,
  }) async {
    if (newMedications.isEmpty || existingMedications.isEmpty) {
      return const <InteractionResult>[];
    }

    final results = <InteractionResult>[];
    final seenRowIds = <String>{};

    for (final newMed in newMedications) {
      final newRxcui = newMed.rxcui?.trim();
      final newGenericRxcui = newMed.genericRxcui?.trim();
      if ((newRxcui == null || newRxcui.isEmpty) &&
          (newGenericRxcui == null || newGenericRxcui.isEmpty)) {
        continue;
      }

      // Lookup rows by ALL rxcuis for this medication (brand + generic
      // + individual ingredients for combination drugs).
      final allRows = <InteractionRow>[];
      final seenLookupRows = <String>{};

      Future<void> lookupAndCollect(String? rxcui) async {
        if (rxcui == null || rxcui.isEmpty) return;
        final rows = await db.lookupByRxcui(rxcui);
        for (final row in rows) {
          if (seenLookupRows.add(row.id)) allRows.add(row);
        }
      }

      await lookupAndCollect(newRxcui);
      await lookupAndCollect(newGenericRxcui);
      for (final ingRxcui in _ingredientRxcuisFor(newMed)) {
        await lookupAndCollect(ingRxcui);
      }
      // Class-based fallback: if rxcui lookups found nothing, try classes.
      if (allRows.isEmpty) {
        for (final cls in _drugClassesFor(newMed)) {
          final classRows = await db.lookupByDrugClass(cls);
          for (final row in classRows) {
            if (seenLookupRows.add(row.id)) allRows.add(row);
          }
        }
      }

      // Build a set of rxcuis + classes from the existing medications
      // to match the OTHER side of each row.
      final existingRxcuis = <String, String>{};
      final existingClasses = <String, String>{};
      for (final med in existingMedications) {
        if (med.rxcui == newMed.rxcui) continue; // skip self
        final rx = med.rxcui?.trim();
        if (rx != null && rx.isNotEmpty) {
          existingRxcuis.putIfAbsent(rx, () => med.name);
        }
        // Also index generic rxcui for existing meds.
        final genRx = med.genericRxcui?.trim();
        if (genRx != null && genRx.isNotEmpty) {
          existingRxcuis.putIfAbsent(genRx, () => med.name);
        }
        for (final cls in _drugClassesFor(med)) {
          existingClasses.putIfAbsent(cls, () => med.name);
        }
      }

      // Collect all rxcuis for the new med (for OTHER-side matching).
      final newMedRxcuis = <String>{};
      if (newRxcui != null && newRxcui.isNotEmpty) newMedRxcuis.add(newRxcui);
      if (newGenericRxcui != null && newGenericRxcui.isNotEmpty) {
        newMedRxcuis.add(newGenericRxcui);
      }

      for (final row in allRows) {
        if (seenRowIds.contains(row.id)) continue;

        // Identify the OTHER side relative to the new medication.
        final String? otherType;
        final String? otherId;
        if (newMedRxcuis.contains(row.agent1Id)) {
          otherType = row.agent2Type;
          otherId = row.agent2Id;
        } else if (newMedRxcuis.contains(row.agent2Id)) {
          otherType = row.agent1Type;
          otherId = row.agent1Id;
        } else {
          // Row came from class lookup — check agent types.
          if (row.agent1Type == 'drug_class') {
            otherType = row.agent2Type;
            otherId = row.agent2Id;
          } else if (row.agent2Type == 'drug_class') {
            otherType = row.agent1Type;
            otherId = row.agent1Id;
          } else {
            continue;
          }
        }

        String? matchedName;
        if (otherType == 'drug') {
          matchedName = existingRxcuis[otherId];
        } else if (otherType == 'drug_class') {
          matchedName = existingClasses[otherId];
        }
        if (matchedName == null) continue;

        seenRowIds.add(row.id);
        results.add(
          InteractionResult.fromRow(
            row,
            source: InteractionSource.pipeline,
            agent1NameOverride: newMed.name,
            agent2NameOverride: matchedName,
          ),
        );
      }
    }

    return results;
  }

  /// Returns the canonical id of whichever side of [row] is NOT [newId].
  /// Returns null if neither canonical column equals [newId] (shouldn't
  /// happen since the caller obtained [row] via
  /// `lookupByCanonicalId(newId)`) or the other side has no canonical
  /// id at all (drug-side rows have `agent_canonical_id` null on the
  /// drug slot).
  static String? _otherCanonicalId(InteractionRow row, String newId) {
    final normalizedNewId = newId.toLowerCase();
    if (row.agent1CanonicalId?.toLowerCase() == normalizedNewId) {
      return row.agent2CanonicalId?.toLowerCase();
    }
    if (row.agent2CanonicalId?.toLowerCase() == normalizedNewId) {
      return row.agent1CanonicalId?.toLowerCase();
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // helpers
  // ---------------------------------------------------------------------------

  /// Lower/trim every id and drop empties + duplicates while preserving
  /// caller order. Mirrors the canonicalization
  /// `stack_nutrient_aggregator` performs so the two checks see the same
  /// id space.
  static List<String> _normalizeCanonicalIds(List<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final id in raw) {
      final norm = id.trim().toLowerCase();
      if (norm.isEmpty) continue;
      if (seen.add(norm)) out.add(norm);
    }
    return out;
  }

  /// Decode a stack row's `ingredient_keys` JSON into a normalized list
  /// of canonical ids.
  ///
  /// Current rows store a JSON list. Older rows may contain the structured
  /// product fingerprint object; use the shared parser so those rows recover
  /// real IDs instead of dropping the stack entry.
  static List<String> _canonicalIdsFor(UserStacksLocalData row) {
    return _normalizeCanonicalIds(
      canonicalIdsFromJsonString(row.ingredientKeys),
    );
  }

  /// Decode a medication row's `drug_classes` JSON into a list of
  /// `class:*` ids. Same lenient handling as
  /// [_canonicalIdsFor]. Class ids are NOT lowercased here — class ids
  /// already ship lowercase from the pipeline (`class:ace_inhibitors`)
  /// and a future case-sensitive class id would be silently corrupted
  /// by a forced lower call.
  static List<String> _drugClassesFor(UserStacksLocalData row) {
    final raw = row.drugClassesCol;
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      final out = <String>[];
      final seen = <String>{};
      for (final e in decoded) {
        if (e == null) continue;
        final s = e.toString().trim();
        if (s.isEmpty) continue;
        if (seen.add(s)) out.add(s);
      }
      return out;
    } on FormatException {
      return const <String>[];
    }
  }

  /// Decode a medication row's `ingredient_rxcuis` JSON into a list of
  /// individual ingredient RXCUIs for combination drugs. Returns empty
  /// for single-ingredient medications. Same lenient handling as
  /// [_drugClassesFor].
  static List<String> _ingredientRxcuisFor(UserStacksLocalData row) {
    final raw = row.ingredientRxcuisCol;
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      final out = <String>[];
      final seen = <String>{};
      for (final e in decoded) {
        if (e == null) continue;
        final s = e.toString().trim();
        if (s.isEmpty) continue;
        if (seen.add(s)) out.add(s);
      }
      return out;
    } on FormatException {
      return const <String>[];
    }
  }
}
