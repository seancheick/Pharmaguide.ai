// Synergy detail — cluster matches, evidence, PMIDs.
//
// **T22 (2026-04-30) — tightened to high-confidence "Works well with"
// chip row.** Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md §8.
//
// Pre-T22: rendered up to 4 clusters as detailed cards with
// explanation, regardless of quality. Sean's complaint: "Popular
// combination" tier 4 noise drowned the genuine "Proven synergy"
// tier 1 signals.
//
// Pipeline shape (verified across 5,450 cluster rows):
//   evidence_tier (1-4): 1=Proven, 2=Supported, 3=Promising, 4=Popular
//   match_count: how many of the cluster's ingredients are in this
//                product
//   all_adequate (0/1): whether all matched ingredients are at
//                       clinically meaningful doses
//   single_ingredient_match (0/1): true when only ONE matched
//
// T22 filter — render only clusters where:
//   - evidence_tier ≤ 2 (Proven or Supported)
//   - match_count ≥ 2 (real synergy, not single-ingredient match)
//   - all_adequate == 1 (doses meaningful)
//
// Sort by tier (asc, 1 best) then match_count (desc). Cap at 3.
// Hide entire section when 0 clusters pass — the section is a
// trust-positive surface, not a "we tried" placeholder.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

class SynergyDetailSection extends StatelessWidget {
  final Map<String, dynamic>? synergyDetail;
  const SynergyDetailSection({super.key, this.synergyDetail});

  /// T22 — filter raw clusters down to the high-confidence subset
  /// shown in the "Works well with" chip row. Pure helper so the
  /// filter rule is unit-testable independent of widget pumping.
  static List<Map<String, dynamic>> filterHighConfidence(
    List<Map<String, dynamic>> clusters,
  ) {
    final filtered = clusters.where((c) {
      final tierRaw = c['evidence_tier'];
      final tier = tierRaw is num ? tierRaw : 99;
      final mcRaw = c['match_count'];
      final matchCount = mcRaw is num ? mcRaw : 0;
      final adequateRaw = c['all_adequate'];
      final allAdequate = adequateRaw == 1 || adequateRaw == true;
      return tier <= 2 && matchCount >= 2 && allAdequate;
    }).toList();
    filtered.sort((a, b) {
      final tierA = (a['evidence_tier'] is num) ? a['evidence_tier'] as num : 99;
      final tierB = (b['evidence_tier'] is num) ? b['evidence_tier'] as num : 99;
      final tierCmp = tierA.compareTo(tierB);
      if (tierCmp != 0) return tierCmp;
      final mcA = (a['match_count'] is num) ? a['match_count'] as num : 0;
      final mcB = (b['match_count'] is num) ? b['match_count'] as num : 0;
      return mcB.compareTo(mcA);
    });
    return filtered.take(3).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (synergyDetail == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final clusters = synergyDetail!.safeMapList('clusters');

    if (clusters.isEmpty) return const SizedBox.shrink();

    // T22 — filter to the top 3 high-confidence clusters. Hide the
    // section entirely when nothing passes (no "0 high-confidence
    // synergies" placeholder).
    final highConfidence = filterHighConfidence(clusters);
    if (highConfidence.isEmpty) return const SizedBox.shrink();

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // T22 — header: lead label + horizontal chip row of top-3
          // high-confidence clusters. Tap a chip → modal explainer.
          Row(
            children: [
              Icon(Icons.hub_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: AppTheme.space6),
              Text(
                'Works well with',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: highConfidence.map((cluster) {
              final name =
                  cluster['name']?.toString() ??
                  cluster['cluster_name']?.toString() ??
                  '';
              final evidenceTier =
                  cluster['evidence_tier']?.toString() ?? '';
              final explanation =
                  cluster['benefit_short']?.toString().isNotEmpty == true
                  ? cluster['benefit_short'].toString()
                  : (cluster['bonus_explanation']?.toString() ?? '');
              final pmids = cluster.safeStringList('pmids');
              return PGPressable(
                onTap: () => _showClusterDetail(
                  context,
                  name: name,
                  evidenceTier: evidenceTier,
                  explanation: explanation,
                  pmids: pmids,
                  singleIngredientMatch: false,
                ),
                pressedScale: 0.96,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.info_outline_rounded,
                        size: 13,
                        color: scheme.onPrimaryContainer.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// T6 (2026-04-29) — show full cluster detail in a bottom sheet so
  /// the user can read the explanation without ellipsis. Inline row
  /// keeps the 3-line summary; tap reveals everything.
  void _showClusterDetail(
    BuildContext context, {
    required String name,
    required String evidenceTier,
    required String explanation,
    required List<String> pmids,
    required bool singleIngredientMatch,
  }) {
    PGModal.bottomSheet<void>(
      context: context,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final scheme = theme.colorScheme;
        return SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space20,
              AppTheme.space12,
              AppTheme.space20,
              AppTheme.space24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (evidenceTier.isNotEmpty) ...[
                      const SizedBox(width: AppTheme.space8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          evidenceTier,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (singleIngredientMatch) ...[
                  const SizedBox(height: AppTheme.space6),
                  Text(
                    'Single-ingredient match',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (explanation.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.space12),
                  // Full text — no maxLines, no ellipsis. This is the
                  // whole point of the sheet.
                  Text(
                    explanation,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
                if (pmids.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.space12),
                  Text(
                    '${pmids.length} published ${pmids.length == 1 ? "study" : "studies"}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
