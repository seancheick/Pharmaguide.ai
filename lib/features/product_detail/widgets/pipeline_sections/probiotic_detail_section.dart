// Probiotic detail — strains, CFU, clinical strains.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

class ProbioticDetailSection extends StatelessWidget {
  final Map<String, dynamic>? probioticDetail;
  const ProbioticDetailSection({super.key, this.probioticDetail});

  @override
  Widget build(BuildContext context) {
    if (probioticDetail == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strains = probioticDetail!.safeMapList('strains');
    final totalCfu = probioticDetail!.safeString('total_cfu');
    // The pipeline emits `clinical_strains` as a list of strain records
    // ([{strain_name, cfu}, ...]) per the M5 detail-blob schema. Older
    // catalogs occasionally emitted just the count as an int, so we accept
    // both shapes here — JSON parsing must degrade gracefully (CLAUDE.md).
    final clinicalStrainsRaw = probioticDetail!['clinical_strains'];
    final clinicalStrains = switch (clinicalStrainsRaw) {
      final List<dynamic> l => l.length,
      final int n => n,
      final num n => n.toInt(),
      _ => 0,
    };
    final prebioticPresent = probioticDetail!.safeBool('prebiotic_present');
    final survivability = probioticDetail!.safeString('survivability');
    // Sprint 2026-05-01 — product-level postbiotic indicator from pipeline.
    // True when probiotic_blends or active ingredient text contains
    // heat-killed / inactivated / postbiotic / paraprobiotic patterns.
    // Independent of clinical_strains matching (which is a high-quality
    // bonus DB, not a presence list). When true, the product's CFU
    // adequacy bonus already excludes inactivated strains; this badge is
    // purely informational so users can see "Postbiotic" content.
    final hasPostbioticStrains = probioticDetail!.safeBool(
      'has_postbiotic_strains',
    );

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
                _InfoChip(
                  label: 'Clinically studied',
                  value: '$clinicalStrains',
                ),
              if (prebioticPresent)
                const _InfoChip(label: 'Prebiotic', value: 'Yes'),
              if (hasPostbioticStrains)
                const _InfoChip(label: 'Postbiotic', value: 'Yes'),
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
                          fontWeight: isClinical
                              ? FontWeight.w600
                              : FontWeight.w400,
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
