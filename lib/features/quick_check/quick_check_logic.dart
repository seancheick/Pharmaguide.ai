// Pure helpers for the "Safe to Take Together?" quick-check feature.
//
// These live outside the widget so they can be unit-tested without a
// Flutter test harness. `QuickCheckV2Screen` is a thin stateful
// consumer on top of this logic + the interaction DB.

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/utils/product_canonical_ids.dart'
    as canonical_ids;
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/features/stack/providers/stack_provider_helpers.dart'
    show canonicalIdsForProduct;

enum QuickCheckItemType { supplement, medication }

/// One side of a Quick Check comparison.
///
/// Supplements carry canonical ingredient ids from the catalog
/// fingerprint. Medications carry RxNorm identifiers and class ids from
/// RxNorm. The UI owns search/selection; this type keeps the interaction
/// lookup logic independent from widget state.
class QuickCheckItem {
  final QuickCheckItemType type;
  final String name;
  final ProductsCoreData? product;
  final String? brandName;
  final int? score;
  final String? rxcui;
  final String? genericRxcui;
  final List<String> ingredientRxcuis;
  final List<String> drugClasses;

  const QuickCheckItem._({
    required this.type,
    required this.name,
    this.product,
    this.brandName,
    this.score,
    this.rxcui,
    this.genericRxcui,
    this.ingredientRxcuis = const <String>[],
    this.drugClasses = const <String>[],
  });

  factory QuickCheckItem.supplement(ProductsCoreData product) {
    return QuickCheckItem._(
      type: QuickCheckItemType.supplement,
      name: product.productName,
      product: product,
      brandName: product.brandName,
      score: product.qualityScoreV4100?.round(),
    );
  }

  factory QuickCheckItem.medication({
    required String name,
    required String rxcui,
    String? genericRxcui,
    List<String> ingredientRxcuis = const <String>[],
    List<String> drugClasses = const <String>[],
  }) {
    return QuickCheckItem._(
      type: QuickCheckItemType.medication,
      name: name,
      rxcui: rxcui,
      genericRxcui: genericRxcui,
      ingredientRxcuis: ingredientRxcuis,
      drugClasses: drugClasses,
    );
  }

  bool get isSupplement => type == QuickCheckItemType.supplement;
  bool get isMedication => type == QuickCheckItemType.medication;

  /// Canonical ingredient ids the interaction DB looks up by. Sourced
  /// via `canonicalIdsForProduct` (the same helper Stack uses) so the
  /// two paths agree on which ids fire which curated rules.
  /// Returns `[]` for medications (which look up by RXCUI + class).
  List<String> get canonicalIds {
    if (!isSupplement || product == null) return const <String>[];
    return canonicalIdsForProduct(product!);
  }

  List<String> get rxcuis {
    final out = <String>{
      if (rxcui != null && rxcui!.trim().isNotEmpty) rxcui!.trim(),
      if (genericRxcui != null && genericRxcui!.trim().isNotEmpty)
        genericRxcui!.trim(),
      for (final id in ingredientRxcuis)
        if (id.trim().isNotEmpty) id.trim(),
    };
    return out.toList(growable: false);
  }

  List<String> get normalizedDrugClasses => drugClasses
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList(growable: false);

  bool get hasInteractionIdentity {
    if (isSupplement) return canonicalIds.isNotEmpty;
    return rxcuis.isNotEmpty || normalizedDrugClasses.isNotEmpty;
  }

  /// True for medications whose RxNorm hydration produced no class
  /// taxonomy and no sibling generic rxcui — meaning we only have the
  /// bare brand RXCUI from the original search. Most curated
  /// medication interaction rows are class-keyed (ACE inhibitors +
  /// Potassium, etc.), so without class data a Quick Check can give a
  /// false-negative. We can't distinguish "RxNorm offline" from "this
  /// drug genuinely has no class taxonomy" — both produce empty
  /// resolution — so callers should surface a "coverage may be
  /// incomplete" notice rather than imply clean check. Always false
  /// for supplements (no RxNorm hydration applies).
  bool get hydrationIncomplete {
    if (!isMedication) return false;
    final hasGeneric = (genericRxcui ?? '').trim().isNotEmpty;
    return drugClasses.isEmpty && ingredientRxcuis.isEmpty && !hasGeneric;
  }

  QuickCheckItem copyWithMedicationResolution({
    String? genericRxcui,
    List<String>? ingredientRxcuis,
    List<String>? drugClasses,
  }) {
    assert(isMedication, 'Only medication items can be RxNorm-hydrated');
    return QuickCheckItem.medication(
      name: name,
      rxcui: rxcui ?? '',
      genericRxcui: genericRxcui ?? this.genericRxcui,
      ingredientRxcuis: ingredientRxcuis ?? this.ingredientRxcuis,
      drugClasses: drugClasses ?? this.drugClasses,
    );
  }
}

/// Extract lowercase canonical ingredient IDs from an
/// `ingredient_fingerprint` JSON payload.
///
/// The pipeline has emitted three shapes over time:
///
/// 1. **Structured (current pipeline output, 2026-04+)** — a map with
///    reserved top-level keys for each ingredient category:
///    ```json
///    {
///      "nutrients": {"potassium": {...}, "magnesium": {...}},
///      "herbs": ["ashwagandha", "ginger"],
///      "categories": ["minerals", "vitamins"],
///      "pharmacological_flags": {"stimulant": false, ...}
///    }
///    ```
///    Canonical ids live INSIDE `nutrients` keys and `herbs` list
///    entries. Top-level keys are structure, not canonical ids.
///
/// 2. **Legacy keyed map** — a map keyed by canonical id with
///    metadata values: `{"calcium": {"dose":500}, "iron": {"dose":18}}`.
///
/// 3. **Bare list** — `["potassium", "magnesium"]`.
///
/// We detect shape 1 by the presence of reserved structure keys; any
/// other map is treated as shape 2. Lists are shape 3.
///
/// Returns an empty list for null, empty string, malformed JSON, or
/// a structured payload whose `nutrients` and `herbs` are both empty.
/// Safety note (Sean 2026-05-17): an empty list here means the
/// product fingerprint can't drive an interaction lookup; callers
/// (Quick Check, StackInteractionChecker) MUST surface "ingredient
/// data is incomplete" rather than imply a clean check.
List<String> extractCanonicalIds(String? fingerprint) {
  return canonical_ids.canonicalIdsFromJsonString(fingerprint);
}

/// Map a [Severity] enum to a [PGBannerTone] for the result card.
///
/// Policy: `contraindicated` and `avoid` → danger. `caution` → caution.
/// Everything else (monitor, safe) → info. Keep in sync with the severity
/// banner doc.
PGBannerTone toneForSeverity(Severity severity) {
  switch (severity) {
    case Severity.contraindicated:
    case Severity.avoid:
      return PGBannerTone.danger;
    case Severity.caution:
      return PGBannerTone.caution;
    case Severity.monitor:
    case Severity.informational:
    case Severity.safe:
      return PGBannerTone.info;
  }
}

bool _sameCanonicalId(String? a, String b) {
  return a?.toLowerCase() == b.toLowerCase();
}

/// Run a pair interaction check between two products.
///
/// Strategy: for each canonical id on product A, look up matching
/// interactions in [db] and keep the ones where the "other" side is in
/// product B's id set. Results are sorted severity-high-to-low.
///
/// Returns an empty list when either product is missing ingredient data.
Future<List<InteractionResult>> runPairCheck(
  ProductsCoreData a,
  ProductsCoreData b,
  InteractionDatabase db,
) async {
  // Use the canonical id resolver Stack uses (`key_ingredient_tags`
  // primary, `ingredient_fingerprint.herbs` fallback) so Quick Check
  // and Stack agree on which rules fire for which products.
  final idsA = canonicalIdsForProduct(a);
  final idsB = canonicalIdsForProduct(b);
  if (idsA.isEmpty || idsB.isEmpty) return const [];

  final results = <InteractionResult>[];
  final seenIds = <String>{};

  for (final idA in idsA) {
    final rows = await db.lookupByCanonicalId(idA);
    for (final row in rows) {
      if (seenIds.contains(row.id)) continue;
      final otherId = _sameCanonicalId(row.agent1CanonicalId, idA)
          ? row.agent2CanonicalId
          : row.agent1CanonicalId;
      if (otherId != null && idsB.contains(otherId.toLowerCase())) {
        seenIds.add(row.id);
        results.add(
          InteractionResult.fromRow(
            row,
            source: InteractionSource.pipeline,
            agent1NameOverride: a.productName,
            agent2NameOverride: b.productName,
          ),
        );
      }
    }
  }

  results.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
  return results;
}

/// Run a Quick Check comparison across supplements and medications.
///
/// This preserves [runPairCheck] for the legacy supplement-only screen
/// and adds the v2 path Sean requested: supplement ↔ medication and
/// medication ↔ medication checks through the same curated interaction
/// database. Empty identity on either side returns an empty list; the
/// caller decides whether to render that as insufficient data.
Future<List<InteractionResult>> runQuickCheckPair(
  QuickCheckItem a,
  QuickCheckItem b,
  InteractionDatabase db,
) async {
  if (!a.hasInteractionIdentity || !b.hasInteractionIdentity) {
    return const <InteractionResult>[];
  }

  if (a.isSupplement && b.isSupplement) {
    return runPairCheck(a.product!, b.product!, db);
  }

  final results = a.isSupplement
      ? await _runSupplementMedicationCheck(a, b, db)
      : b.isSupplement
      ? await _runSupplementMedicationCheck(b, a, db)
      : await _runMedicationMedicationCheck(a, b, db);

  results.sort((a, b) => b.severity.weight.compareTo(a.severity.weight));
  return results;
}

Future<List<InteractionResult>> _runSupplementMedicationCheck(
  QuickCheckItem supplement,
  QuickCheckItem medication,
  InteractionDatabase db,
) async {
  final supplementIds = supplement.canonicalIds;
  final medicationRxcuis = medication.rxcuis.toSet();
  final medicationClasses = medication.normalizedDrugClasses.toSet();
  if (supplementIds.isEmpty ||
      (medicationRxcuis.isEmpty && medicationClasses.isEmpty)) {
    return const <InteractionResult>[];
  }

  final results = <InteractionResult>[];
  final seenRowIds = <String>{};

  for (final supplementId in supplementIds) {
    final rows = await db.lookupByCanonicalId(supplementId);
    for (final row in rows) {
      if (seenRowIds.contains(row.id)) continue;

      final String? otherType;
      final String? otherId;
      if (_sameCanonicalId(row.agent1CanonicalId, supplementId)) {
        otherType = row.agent2Type;
        otherId = row.agent2Id;
      } else if (_sameCanonicalId(row.agent2CanonicalId, supplementId)) {
        otherType = row.agent1Type;
        otherId = row.agent1Id;
      } else {
        continue;
      }

      final matchesMedication =
          (otherType == 'drug' && medicationRxcuis.contains(otherId)) ||
          (otherType == 'drug_class' && medicationClasses.contains(otherId));
      if (!matchesMedication) continue;

      seenRowIds.add(row.id);
      results.add(
        InteractionResult.fromRow(
          row,
          source: InteractionSource.pipeline,
          agent1NameOverride: medication.name,
          agent2NameOverride: supplement.name,
        ),
      );
    }
  }

  return results;
}

Future<List<InteractionResult>> _runMedicationMedicationCheck(
  QuickCheckItem a,
  QuickCheckItem b,
  InteractionDatabase db,
) async {
  final aRxcuis = a.rxcuis.toSet();
  final aClasses = a.normalizedDrugClasses.toSet();
  final bRxcuis = b.rxcuis.toSet();
  final bClasses = b.normalizedDrugClasses.toSet();
  if (aRxcuis.isEmpty && aClasses.isEmpty) {
    return const <InteractionResult>[];
  }
  if (bRxcuis.isEmpty && bClasses.isEmpty) {
    return const <InteractionResult>[];
  }

  // Walk a's side: collect every curated row that mentions a anywhere.
  // Mirror `StackInteractionChecker.checkMedicationPairInteractions`
  // (`lib/services/stack/stack_interaction_checker.dart:412-433`) so
  // the two checks see the same row set. The previous lookupPair-loop
  // was strict on (agent_id, agent_type) and silently dropped rows
  // where a class lived in the `agent_drug_class` cross-ref column —
  // exactly the curated shape that powers Methotrexate+Trimethoprim,
  // Clopidogrel+Omeprazole, ACE inhibitors+Potassium.
  final aRows = <InteractionRow>[];
  final seenLookupRows = <String>{};

  Future<void> collectByRxcui(String rxcui) async {
    if (rxcui.isEmpty) return;
    final rows = await db.lookupByRxcui(rxcui);
    for (final row in rows) {
      if (seenLookupRows.add(row.id)) aRows.add(row);
    }
  }

  for (final rx in aRxcuis) {
    await collectByRxcui(rx);
  }
  // Class fallback always runs (not only when aRows is empty): a
  // user's specific brand RXCUI may have an exact drug-drug row AND a
  // sibling class row, and we want both surfaced. `lookupByDrugClass`
  // returns rows whether the class lives in `agent_id` (type=drug_class)
  // or the `agent_drug_class` cross-ref column.
  for (final cls in aClasses) {
    final rows = await db.lookupByDrugClass(cls);
    for (final row in rows) {
      if (seenLookupRows.add(row.id)) aRows.add(row);
    }
  }

  // Filter: keep rows where the OTHER side matches b's rxcuis (as a
  // drug agent) or b's classes (as a drug_class agent).
  final results = <InteractionResult>[];
  final seenRowIds = <String>{};

  for (final row in aRows) {
    if (!seenRowIds.add(row.id)) continue;

    // Identify which side is "a" and which is "other" relative to a.
    // Order matters: check explicit agent_id+type first (most
    // specific), fall through to the `agent_drug_class` cross-ref
    // column (class-tag-on-a-drug). Capture the other side's
    // cross-ref class too so the match step can also consider it.
    String? otherType;
    String? otherId;
    String? otherDrugClass;
    if (row.agent1Type == 'drug' && aRxcuis.contains(row.agent1Id)) {
      otherType = row.agent2Type;
      otherId = row.agent2Id;
      otherDrugClass = row.agent2DrugClass;
    } else if (row.agent2Type == 'drug' && aRxcuis.contains(row.agent2Id)) {
      otherType = row.agent1Type;
      otherId = row.agent1Id;
      otherDrugClass = row.agent1DrugClass;
    } else if (row.agent1Type == 'drug_class' &&
        aClasses.contains(row.agent1Id)) {
      otherType = row.agent2Type;
      otherId = row.agent2Id;
      otherDrugClass = row.agent2DrugClass;
    } else if (row.agent2Type == 'drug_class' &&
        aClasses.contains(row.agent2Id)) {
      otherType = row.agent1Type;
      otherId = row.agent1Id;
      otherDrugClass = row.agent1DrugClass;
    } else if (aClasses.contains(row.agent1DrugClass)) {
      otherType = row.agent2Type;
      otherId = row.agent2Id;
      otherDrugClass = row.agent2DrugClass;
    } else if (aClasses.contains(row.agent2DrugClass)) {
      otherType = row.agent1Type;
      otherId = row.agent1Id;
      otherDrugClass = row.agent1DrugClass;
    } else {
      continue;
    }

    // b matches when: (1) the other side's agent_id is one of b's
    // rxcuis (as a drug agent), OR (2) the other side's agent_id is
    // one of b's classes (as a drug_class agent), OR (3) the other
    // side carries a cross-ref class tag matching one of b's
    // classes — this last branch is the one the previous lookupPair
    // loop missed.
    final matchesB =
        (otherType == 'drug' && bRxcuis.contains(otherId)) ||
        (otherType == 'drug_class' && bClasses.contains(otherId)) ||
        (otherDrugClass != null && bClasses.contains(otherDrugClass));
    if (!matchesB) continue;

    results.add(
      InteractionResult.fromRow(
        row,
        source: InteractionSource.pipeline,
        agent1NameOverride: a.name,
        agent2NameOverride: b.name,
      ),
    );
  }

  return results;
}
