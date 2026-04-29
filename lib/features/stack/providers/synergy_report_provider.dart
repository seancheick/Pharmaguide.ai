// Synergy detection: finds ingredient clusters in the user's stack and
// returns a [SynergyReport] with matching clusters sorted by evidence tier.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
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

  final supplements = stack
      .where((e) => e.type == 'supplement')
      .toList(growable: false);
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

  final clustersList = clustersData.safeMapList('clusters');
  if (clustersList.isEmpty) {
    return SynergyReport.empty();
  }

  final matches = <SynergyMatch>[];
  int totalBonus = 0;

  for (final cluster in clustersList) {
    final clusterId = cluster.safeString('cluster_id');
    final name = cluster.safeString('name');
    final mechanism = cluster.safeString('mechanism');
    if (clusterId.isEmpty || name.isEmpty || mechanism.isEmpty) continue;

    final ingredients = cluster.safeStringList('ingredients');
    final bonusPoints = cluster.safeInt('bonus_points');
    final evidenceTier = cluster.safeString('evidence_tier', 'limited');
    final citations = cluster.safeStringList('citations');

    // Check if all ingredients in the cluster are in the stack.
    final allPresent = ingredients.every(
      (ing) => stackCanonicalIds.contains(ing),
    );
    if (allPresent) {
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

  return SynergyReport(matches: matches, totalBonusPoints: totalBonus);
});
