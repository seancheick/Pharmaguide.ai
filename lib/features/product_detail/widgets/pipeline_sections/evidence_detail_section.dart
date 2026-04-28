// Evidence & Research detail — clinical matches, PMIDs, claim support.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:url_launcher/url_launcher.dart';

class EvidenceDetailSection extends StatelessWidget {
  final Map<String, dynamic>? evidenceData;
  const EvidenceDetailSection({super.key, this.evidenceData});

  @override
  Widget build(BuildContext context) {
    if (evidenceData == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final matchCount = evidenceData!.safeNum('match_count') ?? 0;
    final clinicalMatches = evidenceData!.safeMapList('clinical_matches');
    final unsubstantiated = evidenceData!.safeStringList('unsubstantiated_claims');

    if (matchCount == 0 && clinicalMatches.isEmpty) return const SizedBox.shrink();

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, size: 18, color: AppTheme.evidenceStrong),
              const SizedBox(width: 6),
              Text(
                'Evidence & Research',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.evidenceStrong.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  '${matchCount.toInt()} matches',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.evidenceStrong,
                  ),
                ),
              ),
            ],
          ),
          if (clinicalMatches.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space12),
            ...clinicalMatches.take(5).map((match) {
              final ingredient = match['ingredient']?.toString() ?? '';
              final evidence = match['evidence_level']?.toString() ?? '';
              final pmids = match.safeStringList('pmids');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: evidence == 'strong'
                          ? AppTheme.severitySafe
                          : AppTheme.severityCaution,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ingredient,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${evidence.isNotEmpty ? "${evidence[0].toUpperCase()}${evidence.substring(1)}" : "Limited"} evidence'
                            '${pmids.isNotEmpty ? " · ${pmids.length} studies" : ""}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (pmids.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          final uri = Uri.tryParse(
                              'https://pubmed.ncbi.nlm.nih.gov/${pmids.first}/');
                          if (uri != null) {
                            launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'PubMed',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
          if (unsubstantiated.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Unsubstantiated claims',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppTheme.severityCaution,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            ...unsubstantiated.map((claim) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 12, color: AppTheme.severityCaution),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          claim,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
