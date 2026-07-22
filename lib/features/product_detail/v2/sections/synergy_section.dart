// Synergy section adapter for Product Detail v2.
//
// Data source: `detailBlob['synergy_detail']` (pipeline-baked from the
// cluster rows in the bundled DB). The section is a trust-positive
// surface and hides when no high-confidence clusters pass the T22 gate.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';

/// T22 — filter raw clusters down to the high-confidence subset shown
/// in the "Works well with" chip row.
List<Map<String, dynamic>> filterHighConfidenceSynergyClusters(
  List<Map<String, dynamic>> clusters,
) {
  final filtered = clusters.where((c) {
    final tierRaw = c['evidence_tier'];
    final tier = tierRaw is num ? tierRaw : 99;
    final matchCountRaw = c['match_count'];
    final matchCount = matchCountRaw is num ? matchCountRaw : 0;
    final adequateRaw = c['all_adequate'];
    final allAdequate = adequateRaw == 1 || adequateRaw == true;
    return tier <= 2 && matchCount >= 2 && allAdequate;
  }).toList();

  filtered.sort((a, b) {
    final tierA = a['evidence_tier'] is num ? a['evidence_tier'] as num : 99;
    final tierB = b['evidence_tier'] is num ? b['evidence_tier'] as num : 99;
    final tierCmp = tierA.compareTo(tierB);
    if (tierCmp != 0) return tierCmp;
    final matchA = a['match_count'] is num ? a['match_count'] as num : 0;
    final matchB = b['match_count'] is num ? b['match_count'] as num : 0;
    return matchB.compareTo(matchA);
  });

  return filtered.take(3).toList(growable: false);
}

/// Build the Synergy section. Returns `SizedBox.shrink()` when the
/// blob is missing `synergy_detail` or no clusters pass the T22 gate.
Widget buildSynergySection({required Map<String, dynamic>? detailBlob}) {
  if (detailBlob == null) return const SizedBox.shrink();
  final synergyDetail = detailBlob['synergy_detail'];
  if (synergyDetail is! Map<String, dynamic>) {
    return const SizedBox.shrink();
  }

  final clusters = synergyDetail.safeMapList('clusters');
  final highConfidence = filterHighConfidenceSynergyClusters(clusters);
  if (highConfidence.isEmpty) return const SizedBox.shrink();

  return _SynergySection(clusters: highConfidence);
}

class _SynergySection extends StatelessWidget {
  final List<Map<String, dynamic>> clusters;

  const _SynergySection({required this.clusters});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('synergy-section-card'),
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_outlined, size: 18, color: V2Colors.accent),
              const SizedBox(width: V2Spacing.space8),
              Text(
                'Works well with',
                style: V2Typography.titleSm(color: V2Colors.fg),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.space12),
          Wrap(
            spacing: V2Spacing.space8,
            runSpacing: V2Spacing.space8,
            children: [
              for (final cluster in clusters)
                _SynergyChip(
                  cluster: cluster,
                  onTap: () => _showClusterDetail(context, cluster),
                ),
            ],
          ),
          // Single-ingredient matches read random without context
          // ("Works well with: Dental & Oral Health" on a CoQ10 bottle)
          // — explain the connection inline with the cluster's authored
          // benefit text. Multi-ingredient clusters are self-evident
          // from the matched ingredients, so no caption there.
          for (final cluster in clusters)
            if (_isSingleIngredientMatch(cluster) &&
                singleMatchCaption(cluster).isNotEmpty) ...[
              const SizedBox(height: V2Spacing.space8),
              Text(
                clusters.length > 1
                    ? '${_clusterName(cluster)} — ${singleMatchCaption(cluster)}'
                    : singleMatchCaption(cluster),
                style: V2Typography.caption(color: V2Colors.fgMuted),
              ),
            ],
        ],
      ),
    );
  }
}

class _SynergyChip extends StatelessWidget {
  final Map<String, dynamic> cluster;
  final VoidCallback onTap;

  const _SynergyChip({required this.cluster, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = _clusterName(cluster);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space12,
            vertical: V2Spacing.space8,
          ),
          decoration: BoxDecoration(
            color: V2Colors.accentTint,
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            border: Border.all(color: V2Colors.accent.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: V2Typography.bodySm(
                  color: V2Colors.accent,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: V2Spacing.space8),
              const Icon(
                Icons.info_outline_rounded,
                size: 13,
                color: V2Colors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showClusterDetail(BuildContext context, Map<String, dynamic> cluster) {
  final name = _clusterName(cluster);
  final evidenceTier = cluster['evidence_tier']?.toString().trim() ?? '';
  final explanation = _clusterExplanation(cluster);
  final pmids = cluster.safeStringList('pmids');

  PGModal.bottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space16,
          V2Spacing.space12,
          V2Spacing.space16,
          V2Spacing.space24,
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
                    style: V2Typography.titleSm(color: V2Colors.fg),
                  ),
                ),
                if (evidenceTier.isNotEmpty) ...[
                  const SizedBox(width: V2Spacing.space8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: V2Spacing.space8,
                      vertical: V2Spacing.space4,
                    ),
                    decoration: BoxDecoration(
                      color: V2Colors.accentTint,
                      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                    ),
                    child: Text(
                      evidenceTier,
                      style: V2Typography.overline(color: V2Colors.accent),
                    ),
                  ),
                ],
              ],
            ),
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: V2Spacing.space12),
              Text(
                explanation,
                style: V2Typography.bodyMedium(color: V2Colors.fgMuted),
              ),
            ],
            if (pmids.isNotEmpty) ...[
              const SizedBox(height: V2Spacing.space12),
              Text(
                '${pmids.length} published '
                '${pmids.length == 1 ? "study" : "studies"}',
                style: V2Typography.label(color: V2Colors.accent),
              ),
            ],
          ],
        ),
      );
    },
  );
}

String _clusterName(Map<String, dynamic> cluster) {
  final name =
      cluster['name']?.toString() ?? cluster['cluster_name']?.toString() ?? '';
  return name.trim().isEmpty ? 'Ingredient combination' : name.trim();
}

bool _isSingleIngredientMatch(Map<String, dynamic> cluster) {
  final raw = cluster['single_ingredient_match'];
  return raw == 1 || raw == true;
}

/// One-line muted caption explaining why a single-ingredient cluster
/// match applies to this product. Prefers the authored `benefit_short`;
/// falls back to the first sentence of the mechanism text, truncated.
/// Never invents copy beyond the authored cluster text.
@visibleForTesting
String singleMatchCaption(Map<String, dynamic> cluster) {
  const maxLength = 140;
  final benefit = cluster['benefit_short']?.toString().trim() ?? '';
  var caption = benefit;
  if (caption.isEmpty) {
    final mechanism = cluster['mechanism']?.toString().trim() ?? '';
    if (mechanism.isEmpty) return '';
    final periodIdx = mechanism.indexOf('. ');
    caption = periodIdx > 0 ? mechanism.substring(0, periodIdx + 1) : mechanism;
  }
  if (caption.length > maxLength) {
    caption = '${caption.substring(0, maxLength - 1).trimRight()}…';
  }
  return caption;
}

String _clusterExplanation(Map<String, dynamic> cluster) {
  final benefit = cluster['benefit_short']?.toString().trim() ?? '';
  if (benefit.isNotEmpty) return benefit;
  return cluster['bonus_explanation']?.toString().trim() ?? '';
}
