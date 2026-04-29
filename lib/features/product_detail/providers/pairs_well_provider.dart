// pairsWellWithStackProvider — finds synergy clusters where adding this
// product to the user's stack would activate at least one new synergy.
//
// A cluster "activates" when:
//   - At least one cluster ingredient is in THIS product's canonical IDs
//   - At least one OTHER cluster ingredient is already in the user's stack
//
// This is intentionally lenient (partial match) to surface potential
// synergies, unlike synergyReportProvider which requires ALL ingredients.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/repositories/reference_data_repository.dart';
import 'package:pharmaguide/features/stack/providers/stack_providers.dart';
import 'package:pharmaguide/services/stack/synergy_result.dart';

/// Returns [SynergyMatch] clusters that would activate if [dsldId] were
/// added to the user's stack. Empty list = no pairs, widget hides itself.
final pairsWellWithStackProvider =
    FutureProvider.family<List<SynergyMatch>, String>((ref, dsldId) async {
      final coreDb = ref.watch(coreDatabaseProvider);

      // Get this product's canonical ingredient IDs.
      final product = await coreDb.findById(dsldId);
      if (product == null) return [];
      final productIds = _productCanonicalIds(
        product.keyIngredientTags,
        product.ingredientFingerprint,
      );
      if (productIds.isEmpty) return [];

      // Get the current stack's canonical IDs (supplements only).
      final stack = await ref.watch(activeStackProvider.future);
      if (stack.isEmpty) return [];
      final stackIds = <String>{};
      for (final entry in stack) {
        if (entry.type != 'supplement') continue;
        final id = entry.dsldId;
        if (id == null || id.isEmpty || id == dsldId) continue;
        final p = await coreDb.findById(id);
        if (p == null) continue;
        stackIds.addAll(
          _productCanonicalIds(p.keyIngredientTags, p.ingredientFingerprint),
        );
      }

      // Load synergy cluster data.
      final refRepo = ReferenceDataRepository();
      final Map<String, dynamic> clustersData;
      try {
        clustersData = await refRepo.loadSynergyClusters();
      } on Object {
        return [];
      }

      final clustersList = clustersData.safeMapList('clusters');
      final matches = <SynergyMatch>[];

      for (final cluster in clustersList) {
        final clusterId = cluster.safeString('cluster_id');
        final name = cluster.safeString('name');
        if (clusterId.isEmpty || name.isEmpty) continue;

        final ingredients = cluster.safeStringList('ingredients');
        if (ingredients.length < 2) continue;

        final mechanism = cluster.safeString('mechanism');
        final bonusPoints = cluster.safeInt('bonus_points');
        final evidenceTier = cluster.safeString('evidence_tier', 'limited');
        final citations = cluster.safeStringList('citations');

        // This product contributes at least one ingredient to the cluster.
        final productContributes = ingredients.any(
          (ing) => productIds.contains(ing),
        );
        // Stack already has at least one complementary ingredient.
        final stackComplements = ingredients.any(
          (ing) => stackIds.contains(ing),
        );

        if (productContributes && stackComplements) {
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
        }
      }

      // Sort: strong first, then by bonus points desc.
      matches.sort((a, b) {
        const tierOrder = {'strong': 0, 'moderate': 1, 'limited': 2};
        final ta = tierOrder[a.evidenceTier] ?? 3;
        final tb = tierOrder[b.evidenceTier] ?? 3;
        if (ta != tb) return ta.compareTo(tb);
        return b.bonusPoints.compareTo(a.bonusPoints);
      });

      return matches;
    });

/// Extracts canonical IDs from a product's `key_ingredient_tags` JSON
/// (primary) and `ingredient_fingerprint.herbs` list (secondary).
/// Mirrors `_canonicalIdsForProduct` in stack_providers.dart.
Set<String> _productCanonicalIds(
  String? keyIngredientTags,
  String? ingredientFingerprint,
) {
  final ids = <String>{};
  if (keyIngredientTags != null && keyIngredientTags.isNotEmpty) {
    try {
      final decoded = jsonDecode(keyIngredientTags);
      if (decoded is List) {
        for (final t in decoded) {
          final s = t.toString().toLowerCase().trim();
          if (s.isNotEmpty) ids.add(s);
        }
      }
    } on FormatException {
      /* fall through */
    }
  }
  if (ingredientFingerprint != null && ingredientFingerprint.isNotEmpty) {
    try {
      final decoded = jsonDecode(ingredientFingerprint);
      if (decoded is Map) {
        final herbs = decoded['herbs'];
        if (herbs is List) {
          for (final h in herbs) {
            final s = h.toString().toLowerCase().trim();
            if (s.isNotEmpty) ids.add(s);
          }
        }
      }
    } on FormatException {
      /* best-effort */
    }
  }
  return ids;
}
