// Pure helpers for the "Safe to Take Together?" quick-check feature.
//
// These live outside the widget so they can be unit-tested without a
// Flutter test harness. The widget (`quick_check_screen.dart`) is a thin
// stateful consumer on top of this logic + the interaction DB.

import 'dart:convert';

import 'package:pharmaguide/core/constants/severity.dart';
import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/core/widgets/pg_severity_banner.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';

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
      score: product.score100Equivalent?.round(),
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

  List<String> get canonicalIds =>
      isSupplement ? extractCanonicalIds(product?.ingredientFingerprint) : [];

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
    return drugClasses.isEmpty &&
        ingredientRxcuis.isEmpty &&
        !hasGeneric;
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

/// Extract lowercase canonical ingredient IDs from a `ingredient_fingerprint`
/// JSON payload.
///
/// The pipeline emits two shapes:
///   - a map keyed by canonical id (values are metadata)
///   - a bare list of canonical ids
///
/// Returns an empty list for null, empty string, or malformed JSON.
List<String> extractCanonicalIds(String? fingerprint) {
  if (fingerprint == null || fingerprint.isEmpty) return const [];
  try {
    final decoded = jsonDecode(fingerprint);
    if (decoded is Map) {
      return decoded.keys.map((k) => k.toString().toLowerCase()).toList();
    }
    if (decoded is List) {
      return decoded
          .where((e) => e != null)
          .map((e) => e.toString().toLowerCase())
          .toList();
    }
  } on FormatException {
    // fall through
  }
  return const [];
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
  final idsA = extractCanonicalIds(a.ingredientFingerprint);
  final idsB = extractCanonicalIds(b.ingredientFingerprint);
  if (idsA.isEmpty || idsB.isEmpty) return const [];

  final results = <InteractionResult>[];
  final seenIds = <String>{};

  for (final idA in idsA) {
    final rows = await db.lookupByCanonicalId(idA);
    for (final row in rows) {
      if (seenIds.contains(row.id)) continue;
      final otherId = (row.agent1CanonicalId == idA)
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
      if (row.agent1CanonicalId == supplementId) {
        otherType = row.agent2Type;
        otherId = row.agent2Id;
      } else if (row.agent2CanonicalId == supplementId) {
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
