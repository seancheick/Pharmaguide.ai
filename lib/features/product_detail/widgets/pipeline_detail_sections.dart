// Pipeline detail sections — renders rich data from the detail blob that
// the pipeline produces. Each section auto-hides when data is absent.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// Evidence & Research detail — clinical matches, PMIDs, claim support
// ---------------------------------------------------------------------------

class EvidenceDetailSection extends StatelessWidget {
  final Map<String, dynamic>? evidenceData;
  const EvidenceDetailSection({super.key, this.evidenceData});

  @override
  Widget build(BuildContext context) {
    if (evidenceData == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final matchCount = evidenceData!['match_count'] as num? ?? 0;
    final clinicalMatches =
        (evidenceData!['clinical_matches'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    final unsubstantiated =
        (evidenceData!['unsubstantiated_claims'] as List?)?.map((e) => e.toString()).toList() ?? [];

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
              final pmids = (match['pmids'] as List?)?.map((e) => e.toString()).toList() ?? [];
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

// ---------------------------------------------------------------------------
// Probiotic detail — strains, CFU, clinical strains
// ---------------------------------------------------------------------------

class ProbioticDetailSection extends StatelessWidget {
  final Map<String, dynamic>? probioticDetail;
  const ProbioticDetailSection({super.key, this.probioticDetail});

  @override
  Widget build(BuildContext context) {
    if (probioticDetail == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strains = (probioticDetail!['strains'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    final totalCfu = probioticDetail!['total_cfu']?.toString() ?? '';
    final clinicalStrains = probioticDetail!['clinical_strains'] as int? ?? 0;
    final prebioticPresent = probioticDetail!['prebiotic_present'] == true;
    final survivability = probioticDetail!['survivability']?.toString() ?? '';

    if (strains.isEmpty && totalCfu.isEmpty) return const SizedBox.shrink();

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.biotech_outlined, size: 18),
              const SizedBox(width: 6),
              Text(
                'Probiotic Profile',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          // Summary row
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              if (totalCfu.isNotEmpty) _InfoChip(label: 'CFU', value: totalCfu),
              if (strains.isNotEmpty)
                _InfoChip(label: 'Strains', value: '${strains.length}'),
              if (clinicalStrains > 0)
                _InfoChip(label: 'Clinically studied', value: '$clinicalStrains'),
              if (prebioticPresent)
                const _InfoChip(label: 'Prebiotic', value: 'Yes'),
              if (survivability.isNotEmpty)
                _InfoChip(label: 'Survivability', value: survivability),
            ],
          ),
          if (strains.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space12),
            ...strains.take(8).map((strain) {
              final name = strain['name']?.toString() ?? '';
              final cfu = strain['cfu']?.toString() ?? '';
              final isClinical = strain['is_clinical'] == true;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      isClinical ? Icons.verified_outlined : Icons.circle,
                      size: isClinical ? 14 : 6,
                      color: isClinical
                          ? AppTheme.severitySafe
                          : scheme.onSurfaceVariant,
                    ),
                    SizedBox(width: isClinical ? 6 : 10),
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: isClinical ? FontWeight.w600 : FontWeight.w400,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    if (cfu.isNotEmpty)
                      Text(
                        cfu,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Certification detail — GMP, purity, heavy metal, label accuracy
// ---------------------------------------------------------------------------

class CertificationDetailSection extends StatelessWidget {
  final Map<String, dynamic>? certificationDetail;
  const CertificationDetailSection({super.key, this.certificationDetail});

  @override
  Widget build(BuildContext context) {
    if (certificationDetail == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    final checks = <(String, bool)>[
      ('GMP Certified', certificationDetail!['gmp'] == true),
      ('Purity Verified', certificationDetail!['purity_verified'] == true),
      ('Heavy Metal Tested', certificationDetail!['heavy_metal_tested'] == true),
      ('Label Accuracy Verified',
          certificationDetail!['label_accuracy_verified'] == true),
    ];

    // Only show if at least one certification is true
    if (!checks.any((c) => c.$2)) return const SizedBox.shrink();

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_outlined, size: 18,
                  color: AppTheme.severitySafe),
              const SizedBox(width: 6),
              Text(
                'Certifications',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          ...checks.map((check) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      check.$2
                          ? Icons.check_circle_rounded
                          : Icons.cancel_outlined,
                      size: 16,
                      color: check.$2
                          ? AppTheme.severitySafe
                          : theme.colorScheme.outlineVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      check.$1,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: check.$2
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )),
          // Third-party program badges (NSF Sport, USP Verified, etc.)
          Builder(builder: (context) {
            final tpData = certificationDetail!['third_party_programs'];
            final programs = (tpData is Map)
                ? ((tpData['programs'] as List?)
                        ?.map((e) => e.toString())
                        .where((s) => s.isNotEmpty)
                        .toList() ??
                    [])
                : <String>[];
            if (programs.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppTheme.space12),
                Text(
                  'Third-Party Verified',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTheme.space8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: programs
                      .map((prog) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.space12,
                                vertical: AppTheme.space6),
                            decoration: BoxDecoration(
                              color: AppTheme.severitySafe
                                  .withValues(alpha: 0.08),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusFull),
                              border: Border.all(
                                color: AppTheme.severitySafe
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 12,
                                  color: AppTheme.severitySafe,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  prog,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.severitySafe,
                                  ),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formulation detail — delivery form, enhancers, botanicals
// ---------------------------------------------------------------------------

class FormulationDetailSection extends StatelessWidget {
  final Map<String, dynamic>? formulationDetail;
  const FormulationDetailSection({super.key, this.formulationDetail});

  @override
  Widget build(BuildContext context) {
    if (formulationDetail == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final deliveryForm = formulationDetail!['delivery_form']?.toString() ?? '';
    final deliveryTier = formulationDetail!['delivery_tier']?.toString() ?? '';
    final enhancers = (formulationDetail!['absorption_enhancers'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final botanicals = (formulationDetail!['standardized_botanicals'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    if (deliveryForm.isEmpty && enhancers.isEmpty && botanicals.isEmpty) {
      return const SizedBox.shrink();
    }

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, size: 18),
              const SizedBox(width: 6),
              Text(
                'Formulation',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          if (deliveryForm.isNotEmpty)
            _DetailRow(
              label: 'Delivery form',
              value: deliveryForm,
              badge: deliveryTier.isNotEmpty ? deliveryTier : null,
            ),
          if (enhancers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Absorption enhancers',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: enhancers
                  .map((e) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.severitySafe.withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusFull),
                          border: Border.all(
                            color: AppTheme.severitySafe.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          e,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.severitySafe,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
          if (botanicals.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Standardized botanicals',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            ...botanicals.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Icon(Icons.eco_outlined,
                          size: 13, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(b,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w500)),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Synergy detail — cluster matches, evidence, PMIDs
// ---------------------------------------------------------------------------

class SynergyDetailSection extends StatelessWidget {
  final Map<String, dynamic>? synergyDetail;
  const SynergyDetailSection({super.key, this.synergyDetail});

  @override
  Widget build(BuildContext context) {
    if (synergyDetail == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final clusters = (synergyDetail!['clusters'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];

    if (clusters.isEmpty) return const SizedBox.shrink();

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                'Synergy Clusters',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  '${clusters.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          ...clusters.take(4).map((cluster) {
            final name = cluster['name']?.toString() ??
                cluster['cluster_name']?.toString() ?? '';
            final evidenceTier = cluster['evidence_tier']?.toString() ?? '';
            final explanation = cluster['bonus_explanation']?.toString() ?? '';
            final pmids = (cluster['pmids'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(AppTheme.space12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(
                      color: scheme.outlineVariant, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (evidenceTier.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              evidenceTier,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (explanation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        explanation,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (pmids.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${pmids.length} published ${pmids.length == 1 ? "study" : "studies"}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Allergen summary banner
// ---------------------------------------------------------------------------

class AllergenSummaryBanner extends StatelessWidget {
  final String? allergenSummary;
  const AllergenSummaryBanner({super.key, this.allergenSummary});

  @override
  Widget build(BuildContext context) {
    if (allergenSummary == null || allergenSummary!.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space12, vertical: AppTheme.space8),
      decoration: BoxDecoration(
        color: AppTheme.severityCaution.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
            color: AppTheme.severityCaution.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: AppTheme.severityCaution),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              allergenSummary!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.severityCaution,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helper widgets
// ---------------------------------------------------------------------------

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final String? badge;
  const _DetailRow({required this.label, required this.value, this.badge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
