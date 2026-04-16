// Synergy detection: finds ingredient clusters in the user's stack and
// returns a [SynergyReport] with matching clusters sorted by evidence tier.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_provider_helpers.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

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
  final hydrated = <HydratedSupplement>[];
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
    hydrated.add(HydratedSupplement(entry: entry, product: product));
  }

  if (hydrated.isEmpty) return SynergyReport.empty();

  // Extract canonical ids from all supplements.
  final stackCanonicalIds = <String>{};
  for (final h in hydrated) {
    final ids = canonicalIdsForProduct(h.product);
    stackCanonicalIds.addAll(ids);
  }

  if (stackCanonicalIds.isEmpty) return SynergyReport.empty();

  // Load synergy clusters and find matches.
  final Map<String, dynamic> clustersData;
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
  );
});
