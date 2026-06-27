import 'package:flutter/foundation.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';

@immutable
class MedicationClassResolution {
  const MedicationClassResolution({
    required this.runtimeClassIds,
    required this.curatedInteractionClassIds,
    required this.mergedInteractionClassIds,
    required this.profileGateClassIds,
  });

  /// RxClass-derived ids already stored by the medication-entry flow
  /// (`class:anti_inflammatory_agents_non_steroidal`, etc.). These are
  /// preserved for audit/debug value, but the curated interaction DB does
  /// not generally match on them.
  final List<String> runtimeClassIds;

  /// PharmaGuide-curated interaction ids (`class:nsaids`) resolved from
  /// bundled `drug_class_map` membership first, then the narrow fallback map.
  final List<String> curatedInteractionClassIds;

  /// The list safe to persist back into `user_stacks_local.drug_classes`.
  /// Runtime ids are preserved and curated ids are appended once.
  final List<String> mergedInteractionClassIds;

  /// Profile-gate vocabulary ids (`nsaids`) derived from curated ids.
  final List<String> profileGateClassIds;
}

class MedicationClassBridge {
  const MedicationClassBridge({required InteractionDatabase db}) : _db = db;

  final InteractionDatabase _db;

  /// Small pipeline-authored bridge for RxClass slugs that are not covered by
  /// the bundled RxCUI membership map yet. Membership remains authoritative;
  /// this fallback only fills gaps and must stay deliberately narrow.
  static const Map<String, String> _rxClassFallbackToCurated = {
    'class:anti_inflammatory_agents_non_steroidal': 'class:nsaids',
    'class:cyclooxygenase_inhibitors': 'class:nsaids',
    'class:propionic_acid_derivatives': 'class:nsaids',
  };

  // Aspirin identities used only to prevent RxClass fallback from promoting
  // aspirin into the generic NSAID class. This is not dose parsing and does
  // not create a "safe" claim; full-dose aspirin remains a future authored
  // clinical-rule decision.
  static const Set<String> _aspirinRxcuis = {
    '1191', // aspirin ingredient
    '243670', // aspirin 81 MG Oral Tablet
    '315431', // aspirin 81 MG
  };
  static const Set<String> _antiplateletClasses = {'class:antiplatelet_agents'};
  static const Map<String, String> _profileGateClassOverrides = {
    'class:antiplatelet_agents': 'antiplatelets',
  };
  static const Map<String, List<String>> _offlineIngredientRxcuiAliases = {
    // RxNorm Motrin brand/product concepts that resolve to ibuprofen (5640).
    // This prevents a silent offline miss if autocomplete succeeds but the
    // follow-up brand -> ingredient hydration fails.
    '202488': ['5640'], // Motrin
    '1182821': ['5640'], // Motrin Pill
    '1182818': ['5640'], // Motrin Oral Product
    '1296120': ['5640'], // Motrin Chewable Product
    '1182817': ['5640'], // Motrin Oral Liquid Product
    '93358': ['5640'], // ibuprofen Oral Tablet [Motrin]
    '606989': ['5640'], // ibuprofen Oral Capsule [Motrin]
    '792241': ['5640'], // ibuprofen Chewable Tablet [Motrin]
    '544392': ['5640'], // ibuprofen Oral Suspension [Motrin]
  };

  Future<MedicationClassResolution> resolve({
    String? selectedRxcui,
    String? genericRxcui,
    List<String> ingredientRxcuis = const <String>[],
    List<String> runtimeClassIds = const <String>[],
  }) async {
    final rxcuis = _expandOfflineAliases(
      _normalizeRxcuis([selectedRxcui, genericRxcui, ...ingredientRxcuis]),
    );
    final runtime = _normalizeClassIds(runtimeClassIds);

    final curated = <String>[];
    final seenCurated = <String>{};
    for (final rxcui in rxcuis) {
      final classes = await _db.drugClassesForRxcui(rxcui);
      for (final classId in _normalizeClassIds(classes)) {
        if (seenCurated.add(classId)) curated.add(classId);
      }
    }

    final hasAspirinIdentity =
        rxcuis.any(_aspirinRxcuis.contains) ||
        curated.any(_antiplateletClasses.contains);

    for (final runtimeId in runtime) {
      final fallback = _rxClassFallbackToCurated[runtimeId];
      if (fallback == null) continue;
      if (fallback == 'class:nsaids' && hasAspirinIdentity) continue;
      if (seenCurated.add(fallback)) curated.add(fallback);
    }

    final merged = <String>[];
    final seenMerged = <String>{};
    for (final classId in [...runtime, ...curated]) {
      if (seenMerged.add(classId)) merged.add(classId);
    }

    return MedicationClassResolution(
      runtimeClassIds: runtime,
      curatedInteractionClassIds: curated,
      mergedInteractionClassIds: merged,
      profileGateClassIds: _profileGateIds(curated),
    );
  }

  static List<String> _normalizeRxcuis(Iterable<String?> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty) continue;
      if (seen.add(normalized)) out.add(normalized);
    }
    return out;
  }

  static List<String> _normalizeClassIds(Iterable<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final normalized = trimmed.startsWith('class:')
          ? trimmed
          : 'class:$trimmed';
      if (seen.add(normalized)) out.add(normalized);
    }
    return out;
  }

  static List<String> _expandOfflineAliases(List<String> rxcuis) {
    final out = <String>[];
    final seen = <String>{};
    for (final rxcui in rxcuis) {
      if (seen.add(rxcui)) out.add(rxcui);
      for (final alias
          in _offlineIngredientRxcuiAliases[rxcui] ?? const <String>[]) {
        if (seen.add(alias)) out.add(alias);
      }
    }
    return out;
  }

  static List<String> _profileGateIds(Iterable<String> classIds) {
    final out = <String>[];
    final seen = <String>{};
    for (final classId in classIds) {
      if (!classId.startsWith('class:')) continue;
      final profileId =
          _profileGateClassOverrides[classId] ?? classId.substring(6);
      if (profileId.isEmpty) continue;
      if (seen.add(profileId)) out.add(profileId);
    }
    return out;
  }
}
