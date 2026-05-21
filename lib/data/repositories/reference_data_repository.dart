import 'dart:convert';
import 'package:flutter/services.dart';

class ReferenceDataRepository {
  Map<String, dynamic>? _taxonomyCache;
  Map<String, dynamic>? _goalsCache;
  Map<String, dynamic>? _rdaCache;
  Map<String, dynamic>? _timingCache;
  Map<String, dynamic>? _synergyClustersCache;
  Map<String, dynamic>? _bannedRecalledCache;
  Map<String, dynamic>? _depletionsCache;

  Future<Map<String, dynamic>> loadClinicalRiskTaxonomy() async {
    _taxonomyCache ??= await _loadJson(
      'assets/reference_data/clinical_risk_taxonomy.json',
    );
    return _taxonomyCache!;
  }

  Future<Map<String, dynamic>> loadGoalMappings() async {
    _goalsCache ??= await _loadJson(
      'assets/reference_data/user_goals_to_clusters.json',
    );
    return _goalsCache!;
  }

  Future<Map<String, dynamic>> loadRdaOptimalUls() async {
    _rdaCache ??= await _loadJson('assets/reference_data/rda_optimal_uls.json');
    return _rdaCache!;
  }

  Future<Map<String, dynamic>> loadTimingRules() async {
    _timingCache ??= await _loadJson('assets/reference_data/timing_rules.json');
    return _timingCache!;
  }

  Future<Map<String, dynamic>> loadSynergyClusters() async {
    _synergyClustersCache ??= normalizeSynergyClusterData(
      await _loadJson('assets/reference_data/synergy_cluster.json'),
    );
    return _synergyClustersCache!;
  }

  Future<Map<String, dynamic>> loadBannedRecalledIngredients() async {
    _bannedRecalledCache ??= normalizeBannedRecalledData(
      await _loadJson('assets/reference_data/banned_recalled_ingredients.json'),
    );
    return _bannedRecalledCache!;
  }

  Future<Map<String, dynamic>> loadMedicationDepletions() async {
    _depletionsCache ??= await _loadJson(
      'assets/reference_data/medication_depletions.json',
    );
    return _depletionsCache!;
  }

  Future<Map<String, dynamic>> _loadJson(String path) async {
    final raw = await rootBundle.loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    // Reference assets are bundled with the app, so a non-map shape here
    // means a corrupt or wrongly-shaped asset shipped — surface that as a
    // hard failure rather than silently returning empty data, since
    // downstream callers depend on these maps being non-empty.
    throw FormatException('Reference data at $path is not a JSON object');
  }
}

/// Normalizes pipeline-owned banned_recalled_ingredients.json into the compact
/// shape consumed by the stack recall provider.
///
/// The pipeline source uses top-level `ingredients` and keeps identity,
/// regulatory, and authored safety fields separate. Flutter consumers read
/// `recalled_ingredients` with the narrower field names used by
/// [RecalledIngredientAlert]. Keep the asset byte-identical to the pipeline
/// file and adapt at this boundary.
Map<String, dynamic> normalizeBannedRecalledData(Map<String, dynamic> raw) {
  final existing = raw['recalled_ingredients'];
  if (existing is List) {
    return raw;
  }

  final pipelineEntries = raw['ingredients'];
  if (pipelineEntries is! List) {
    return raw;
  }

  return {
    ...raw,
    'recalled_ingredients': pipelineEntries
        .whereType<Map<String, dynamic>>()
        .map(_normalizeBannedRecalledEntry)
        .toList(growable: false),
  }..remove('ingredients');
}

Map<String, dynamic> _normalizeBannedRecalledEntry(Map<String, dynamic> entry) {
  final status = entry['status']?.toString() ?? 'warning';
  final legalStatus = entry['legal_status_enum']?.toString() ?? '';
  return {
    'canonical_id':
        entry['canonical_id']?.toString() ?? entry['id']?.toString() ?? '',
    'common_names': _commonNamesForBannedEntry(entry),
    'recall_status': entry['recall_status']?.toString() ?? status,
    'regulatory_basis':
        entry['regulatory_basis']?.toString() ??
        [legalStatus, status].where((v) => v.trim().isNotEmpty).join(' - '),
    'reason': entry['reason']?.toString() ?? '',
    'effective_date':
        entry['effective_date']?.toString() ??
        entry['regulatory_date']?.toString() ??
        '',
    'severity':
        entry['severity']?.toString() ??
        _recallSeverity(entry['clinical_risk_enum']?.toString()),
    'safety_warning': entry['safety_warning']?.toString() ?? '',
    'safety_warning_one_liner':
        entry['safety_warning_one_liner']?.toString() ?? '',
    'ban_context': entry['ban_context']?.toString() ?? '',
  };
}

List<String> _commonNamesForBannedEntry(Map<String, dynamic> entry) {
  final names = <String>[];
  final commonNames = entry['common_names'];
  if (commonNames is List) {
    names.addAll(commonNames.map((v) => v.toString()));
  }
  final standardName = entry['standard_name']?.toString();
  if (standardName != null) names.add(standardName);
  final aliases = entry['aliases'];
  if (aliases is List) {
    names.addAll(aliases.map((v) => v.toString()));
  }

  final seen = <String>{};
  return names
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .where((name) => seen.add(name.toLowerCase()))
      .toList(growable: false);
}

String _recallSeverity(String? clinicalRisk) {
  switch (clinicalRisk) {
    case 'critical':
      return 'critical';
    case 'high':
    case 'moderate':
    case 'dose_dependent':
      return 'major';
    default:
      return 'warning';
  }
}

/// Normalizes pipeline-owned synergy_cluster.json into the compact shape
/// consumed by local Flutter stack/pairs-well providers.
///
/// The pipeline source of truth uses top-level `synergy_clusters` with fields
/// such as `id`, `standard_name`, `synergy_mechanism`, and `sources`. The
/// existing Flutter consumers read `clusters` with `cluster_id`, `name`,
/// `mechanism`, `bonus_points`, and `citations`. Keep the asset byte-identical
/// to the pipeline file and adapt at this boundary.
Map<String, dynamic> normalizeSynergyClusterData(Map<String, dynamic> raw) {
  final existingClusters = raw['clusters'];
  if (existingClusters is List) {
    return raw;
  }

  final pipelineClusters = raw['synergy_clusters'];
  if (pipelineClusters is! List) {
    return raw;
  }

  return {
    ...raw,
    'clusters': pipelineClusters
        .whereType<Map<String, dynamic>>()
        .map(_normalizeSynergyCluster)
        .toList(growable: false),
  }..remove('synergy_clusters');
}

Map<String, dynamic> _normalizeSynergyCluster(Map<String, dynamic> cluster) {
  final evidenceTier = _normalizeEvidenceTier(cluster['evidence_tier']);
  final citations = _extractCitations(cluster);
  final canonicalIds =
      (cluster['canonical_ids'] as List?)
          ?.map((id) => id.toString())
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false) ??
      const <String>[];
  final ingredientIds = canonicalIds.isNotEmpty
      ? canonicalIds
      : (cluster['ingredients'] as List?)
                ?.map((id) => id.toString())
                .where((id) => id.trim().isNotEmpty)
                .toList(growable: false) ??
            const <String>[];

  return {
    'cluster_id':
        cluster['cluster_id']?.toString() ?? cluster['id']?.toString(),
    'name':
        cluster['name']?.toString() ??
        cluster['cluster_name']?.toString() ??
        cluster['standard_name']?.toString(),
    'ingredients': ingredientIds,
    'evidence_tier': evidenceTier,
    'mechanism':
        cluster['mechanism']?.toString() ??
        cluster['synergy_mechanism']?.toString() ??
        cluster['note']?.toString() ??
        '',
    'bonus_points': cluster['bonus_points'] is num
        ? (cluster['bonus_points'] as num).round()
        : 1,
    'citations': citations,
  };
}

String _normalizeEvidenceTier(dynamic value) {
  if (value is num) {
    if (value <= 1) return 'strong';
    if (value == 2) return 'moderate';
    return 'limited';
  }

  final tier = value?.toString().trim().toLowerCase();
  if (tier == '1' || tier == 'tier 1' || tier == 'strong') {
    return 'strong';
  }
  if (tier == '2' || tier == 'tier 2' || tier == 'moderate') {
    return 'moderate';
  }
  return 'limited';
}

List<String> _extractCitations(Map<String, dynamic> cluster) {
  final pmids =
      (cluster['pmids'] as List?)
          ?.map((id) => id.toString())
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false) ??
      const <String>[];
  if (pmids.isNotEmpty) return pmids;

  final sources = cluster['sources'];
  if (sources is! List) return const <String>[];

  return sources
      .whereType<Map<String, dynamic>>()
      .map((source) {
        final pmid = source['pmid']?.toString().trim();
        if (pmid != null && pmid.isNotEmpty) return pmid;
        return source['url']?.toString().trim() ?? '';
      })
      .where((citation) => citation.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
