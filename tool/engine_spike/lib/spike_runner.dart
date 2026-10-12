// Server-side harness for the REAL engine classes in lib/ (compiled through the
// overlay; see tool/engine_spike/make_overlay.py).
//
// `preAddCheck` and `depletionReport` are line-for-line mirrors of the
// orchestration that today lives inside Riverpod providers in
// lib/features/stack/providers/stack_safety_providers.dart
// (`safetyCheckForAddProvider`, `depletionReportProvider`). That duplication is
// the spike's main finding: production must EXTRACT these bodies into pure
// functions in lib/ that both the providers and the service call. Everything
// they call (StackInteractionChecker, MedicationClassBridge,
// MedicationIdentitySnapshot, canonicalIdsForProduct, parseFingerprint,
// DepletionChecker, activateMedicationDepletionsArtifact) is the unchanged
// lib/ code.
import 'dart:convert';

import 'package:pharmaguide/core/models/interaction_result.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
// Pure (no Riverpod) helpers the providers use; imported, not copied.
import 'package:pharmaguide/features/stack/providers/stack_provider_helpers.dart'
    show canonicalIdsForProduct, parseFingerprint;
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';
import 'package:pharmaguide/services/stack/stack_dose_summer.dart';
import 'package:pharmaguide/services/stack/stack_interaction_checker.dart';

class SpikeData {
  SpikeData({
    required this.db,
    required this.products,
    required this.stack,
    required this.depletionsJson,
  });

  final InteractionDatabase db;
  final Map<String, ProductsCoreData> products;
  final List<UserStacksLocalData> stack;
  final Map<String, dynamic> depletionsJson;

  static final DateTime _epoch = DateTime.utc(2026, 10, 12);

  static UserStacksLocalData stackRow(Map<String, dynamic> j) =>
      UserStacksLocalData(
        id: j['id'] as String,
        type: j['type'] as String,
        name: j['name'] as String,
        dsldId: j['dsld_id'] as String?,
        rxcui: j['rxcui'] as String?,
        ingredientKeys: j['ingredient_keys'] as String?,
        drugClassesCol: j['drug_classes'] as String?,
        genericRxcui: j['generic_rxcui'] as String?,
        addedAt: _epoch,
        clientUpdatedAt: _epoch,
      );

  factory SpikeData.parse({
    required String stackJson,
    required String interactionsJson,
    required String drugClassMapJson,
    required String productsJson,
    required String depletionsJson,
  }) {
    final stack = jsonDecode(stackJson) as Map<String, dynamic>;
    return SpikeData(
      db: InteractionDatabase.fromSqlJson(
        interactionsJson: interactionsJson,
        drugClassMapJson: drugClassMapJson,
      ),
      products: {
        for (final p in jsonDecode(productsJson) as List)
          (p as Map<String, dynamic>)['dsld_id'].toString():
              ProductsCoreData.fromSqlJson(p),
      },
      stack: [
        for (final e in stack['stack'] as List)
          stackRow(e as Map<String, dynamic>),
      ],
      depletionsJson: jsonDecode(depletionsJson) as Map<String, dynamic>,
    );
  }
}

/// Mirror of `safetyCheckForAddProvider` (no detail blobs server-side in the
/// spike, exactly like the app when the blob fetch returns null: dose totals
/// are empty and `checksIncomplete` is set).
Future<({List<InteractionResult> results, bool checksIncomplete})> preAddCheck(
  SpikeData d,
  String dsldId,
) async {
  final candidate = d.products[dsldId];
  if (d.stack.isEmpty) return (results: <InteractionResult>[], checksIncomplete: false);
  if (candidate == null) return (results: <InteractionResult>[], checksIncomplete: true);
  final interactionDb = d.db;

  final supplementRows =
      d.stack.where((e) => e.type == 'supplement').toList(growable: false);
  final medicationRows =
      d.stack.where((e) => e.type == 'medication').toList(growable: false);

  var checksIncomplete = false;
  final stackProducts = <ProductsCoreData>[];
  for (final entry in supplementRows) {
    final id = entry.dsldId;
    if (id == null || id.isEmpty) continue;
    final product = d.products[id];
    if (product != null) {
      stackProducts.add(product);
    } else {
      checksIncomplete = true;
    }
  }

  final candidateIds = canonicalIdsForProduct(candidate);
  final checker = StackInteractionChecker();
  // _pairwiseDoseTotalsFor with every blob == null → incomplete, empty totals.
  checksIncomplete = true;
  const pairwiseDoseTotals = <String, StackDoseTotal>{};

  final combined = <InteractionResult>[];
  final seenIds = <String>{};
  void addAll(Iterable<InteractionResult> hits) {
    for (final r in hits) {
      if (seenIds.add(r.id)) combined.add(r);
    }
  }

  if (candidateIds.isNotEmpty && supplementRows.isNotEmpty) {
    addAll(
      await checker.checkSupplementPairInteractions(
        newProductCanonicalIds: candidateIds,
        stackSupplements: supplementRows,
        db: interactionDb,
        newProductName: candidate.productName,
        stackDoseTotals: pairwiseDoseTotals,
      ),
    );
  }

  if (candidateIds.isNotEmpty && medicationRows.isNotEmpty) {
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
        stackDoseTotals: pairwiseDoseTotals,
      ),
    );
  }

  if (stackProducts.isNotEmpty) {
    bool flag(int? v) => v == 1;
    addAll(
      checker.checkSafety(
        newProductFingerprint: parseFingerprint(candidate.ingredientFingerprint),
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
        stackProductNames:
            stackProducts.map((p) => p.productName).toList(growable: false),
        newProductName: candidate.productName,
      ),
    );
  }

  return (results: combined, checksIncomplete: checksIncomplete);
}

/// Mirror of `_normalizeMedicationRowsForSafety` (stack_safety_providers.dart).
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
    if (mergedClasses.isEmpty) identityIncomplete = true;
    final nextClassesJson =
        mergedClasses.isEmpty ? null : jsonEncode(mergedClasses);
    out.add(
      nextClassesJson == med.drugClassesCol
          ? med
          : med.withDrugClasses(nextClassesJson),
    );
  }
  return (rows: out, identityIncomplete: identityIncomplete);
}

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

/// Mirror of `depletionReportProvider` (no detail blobs → no stack doses).
({String status, List<DepletionMatch> matches}) depletionReport(SpikeData d) {
  final medications = d.stack
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
  if (medications.isEmpty) {
    return (status: MedNutrientLoadStatus.loaded.name, matches: const []);
  }
  final load = activateMedicationDepletionsArtifact(d.depletionsJson);
  if (load.status == MedNutrientLoadStatus.unavailable) {
    return (status: load.status.name, matches: const []);
  }
  final coveredIds = <String>{};
  for (final supp in d.stack.where((e) => e.type == 'supplement')) {
    if (supp.dsldId == null) continue;
    final tags = d.products[supp.dsldId!]?.keyIngredientTags;
    if (tags != null) {
      try {
        final decoded = jsonDecode(tags);
        if (decoded is List) {
          for (final tag in decoded) {
            coveredIds.add(tag.toString().toLowerCase());
          }
        }
      } on FormatException {
        // Mirrors the provider: malformed tags are skipped.
      }
    }
    // blob == null → `continue` in the provider; no nutrient items.
  }
  return (
    status: load.status.name,
    matches: DepletionChecker().check(
      medications: const [],
      medicationIdentities: medications,
      depletionsData: load.data,
      stackCanonicalIds: coveredIds,
      stackDoses: const [],
    ),
  );
}

/// Stack-wide pivot used by `stackSafetyReportProvider` sections 1-2 (every
/// supplement checked as "new" against the rest and against every medication).
/// Benchmark only: this is the O(n^2) part of the full report.
Future<int> stackPivot(SpikeData d) async {
  final checker = StackInteractionChecker();
  final supplements = d.stack.where((e) => e.type == 'supplement').toList();
  final meds = (await _normalizeMedicationRowsForSafety(
    d.stack.where((e) => e.type == 'medication').toList(),
    MedicationClassBridge(db: d.db),
  )).rows;
  final seen = <String>{};
  for (var i = 0; i < supplements.length; i++) {
    final self = supplements[i];
    final product = d.products[self.dsldId];
    if (product == null) continue;
    final ids = canonicalIdsForProduct(product);
    final others = [
      for (var j = 0; j < supplements.length; j++)
        if (j != i) supplements[j],
    ];
    for (final r in await checker.checkSupplementPairInteractions(
      newProductCanonicalIds: ids,
      stackSupplements: others,
      db: d.db,
      newProductName: self.name,
    )) {
      seen.add(r.id);
    }
    for (final r in await checker.checkMedicationInteractions(
      newProductCanonicalIds: ids,
      stackMedications: meds,
      db: d.db,
      newProductName: self.name,
    )) {
      seen.add(r.id);
    }
  }
  for (final r in await checker.checkMedicationFoodAdvisories(
    stackMedications: meds,
    db: d.db,
  )) {
    seen.add(r.id);
  }
  return seen.length;
}

/// 10-item benchmark stack (7 supplements + 3 medications) over the FULL live
/// interaction ruleset.
SpikeData benchData(SpikeData base, String allLiveInteractionsJson,
    String drugClassMapJson) {
  const tags = [
    'fish_oil', 'garlic', 'vitamin_e', 'turmeric', 'ginseng', 'coq10',
    'cranberry',
  ];
  final products = <String, ProductsCoreData>{...base.products};
  final stack = <UserStacksLocalData>[];
  for (var i = 0; i < tags.length; i++) {
    final id = 'bench-${tags[i]}';
    products[id] = ProductsCoreData(
      dsldId: id,
      productName: 'Bench ${tags[i]}',
      keyIngredientTags: '["${tags[i]}"]',
    );
    stack.add(SpikeData.stackRow({
      'id': 'stack-$id',
      'type': 'supplement',
      'name': 'Bench ${tags[i]}',
      'dsld_id': id,
      'ingredient_keys': '["${tags[i]}"]',
    }));
  }
  for (final med in [
    ('Warfarin', '11289'),
    ('Sertraline', '36437'),
    ('Ibuprofen', '5640'),
  ]) {
    stack.add(SpikeData.stackRow({
      'id': 'stack-${med.$2}',
      'type': 'medication',
      'name': med.$1,
      'rxcui': med.$2,
    }));
  }
  return SpikeData(
    db: InteractionDatabase.fromSqlJson(
      interactionsJson: allLiveInteractionsJson,
      drugClassMapJson: drugClassMapJson,
    ),
    products: products,
    stack: stack,
    depletionsJson: base.depletionsJson,
  );
}
