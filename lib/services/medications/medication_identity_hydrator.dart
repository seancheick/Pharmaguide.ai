import 'dart:convert';

import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/medications/medication_class_bridge.dart';
import 'package:pharmaguide/services/medications/medication_identity_status.dart';
import 'package:pharmaguide/services/medications/rxnorm_api_service.dart';

class MedicationIdentityHydrator {
  MedicationIdentityHydrator({
    required this._userDb,
    required this._rxNorm,
    this._classBridge,
  });

  final UserDatabase _userDb;
  final RxNormApiService _rxNorm;
  final MedicationClassBridge? _classBridge;

  Future<int> rehydrateActiveStackMedications() async {
    final stack = await _userDb.getActiveStack();
    var updated = 0;
    for (final row in stack.where((e) => e.type == 'medication')) {
      if (await rehydrateMedication(row)) updated++;
    }
    return updated;
  }

  Future<bool> rehydrateMedication(UserStacksLocalData row) async {
    if (row.type != 'medication') return false;
    final snapshot = MedicationIdentitySnapshot.fromStackRow(row);
    if (!snapshot.hasExactRxcui) return false;
    if (_classBridge == null &&
        snapshot.hasDrugClasses &&
        (snapshot.hasGenericRxcui || snapshot.hasIngredientRxcuis)) {
      return false;
    }

    final rxcui = snapshot.rxcui!;
    final needsNetworkHydration =
        !snapshot.hasDrugClasses ||
        (!snapshot.hasGenericRxcui && !snapshot.hasIngredientRxcuis);
    final resolvedGenerics = needsNetworkHydration
        ? await _rxNorm.resolveGenericRxcuis(rxcui)
        : const <String>[];
    final resolvedClasses = needsNetworkHydration
        ? await _rxNorm.getClasses(rxcui)
        : const <String>[];

    final nextGeneric =
        snapshot.genericRxcui ??
        (resolvedGenerics.isNotEmpty ? resolvedGenerics.first : null);
    final nextIngredients = snapshot.ingredientRxcuis.isNotEmpty
        ? snapshot.ingredientRxcuis
        : (resolvedGenerics.length > 1 ? resolvedGenerics : const <String>[]);
    final mergedClasses = _mergeIdentityLists(
      snapshot.drugClassIds,
      resolvedClasses,
    );
    final bridge = _classBridge;
    final nextClasses = bridge == null
        ? mergedClasses
        : (await bridge.resolve(
            selectedRxcui: snapshot.rxcui,
            genericRxcui: nextGeneric,
            ingredientRxcuis: nextIngredients,
            runtimeClassIds: mergedClasses,
          )).mergedInteractionClassIds;

    final nextSnapshot = MedicationIdentitySnapshot(
      name: snapshot.name,
      rxcui: snapshot.rxcui,
      genericRxcui: nextGeneric,
      ingredientRxcuis: nextIngredients,
      drugClassIds: nextClasses,
    );
    if (nextSnapshot.status.index <= snapshot.status.index &&
        nextGeneric == snapshot.genericRxcui &&
        _sameList(nextIngredients, snapshot.ingredientRxcuis) &&
        _sameList(nextClasses, snapshot.drugClassIds)) {
      return false;
    }

    await _userDb.updateMedicationIdentity(
      id: row.id,
      genericRxcui: nextGeneric,
      ingredientRxcuisJson: nextIngredients.isEmpty
          ? null
          : jsonEncode(nextIngredients),
      drugClassesJson: nextClasses.isEmpty ? null : jsonEncode(nextClasses),
    );
    return true;
  }

  static List<String> _mergeIdentityLists(
    List<String> current,
    List<String> resolved,
  ) {
    final out = <String>[];
    final seen = <String>{};
    for (final value in [...current, ...resolved]) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) out.add(trimmed);
    }
    return out;
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
