// Probiotic detail — strains, CFU, clinical strains.
//
// Pipeline shape (FINAL_EXPORT_SCHEMA_V1.md `probiotic_detail`):
//   total_cfu            number      — raw CFU count (e.g. 25e9)
//   total_billion_count  number      — count in billions (e.g. 25.0)
//   total_cfu_label      string      — pre-formatted "25 billion CFU"
//   total_strain_count   number      — flat strain count
//   has_survivability_coating bool   — survivability technology present
//   survivability_reason string      — which technology / brand marker matched
//   has_postbiotic_strains bool      — heat-killed / inactivated / lysate present
//   prebiotic_present    bool
//   prebiotic_name       string
//   probiotic_blends     list[blend] — each {name, strains[strain_str], strain_count, cfu_data{}}
//   clinical_strains     list[record] — {strain, clinical_id, cfu_per_day,
//                                       evidence_level, is_inactivated, ...}
//
// Earlier versions of this file read `strains` (no such top-level key) and
// `total_cfu` via safeString (silently empty for numeric values). Rewired
// 2026-05-05 to the canonical shape above.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

class ProbioticDetailSection extends StatelessWidget {
  final Map<String, dynamic>? probioticDetail;
  const ProbioticDetailSection({super.key, this.probioticDetail});

  /// Flatten probiotic_blends[].strains[] into a single ordered list.
  /// Returns the raw strain strings ("Lactobacillus acidophilus", etc.).
  List<String> _flattenStrainNames() {
    final blends = probioticDetail!.safeMapList('probiotic_blends');
    final out = <String>[];
    for (final blend in blends) {
      final raw = blend['strains'];
      if (raw is List) {
        for (final s in raw) {
          final name = s?.toString() ?? '';
          if (name.isNotEmpty && !out.contains(name)) out.add(name);
        }
      }
    }
    return out;
  }

  /// Format a numeric CFU-per-day value for a per-strain row. Returns
  /// "5 billion" / "5.5 billion" / "" (when missing or non-numeric).
  String _formatStrainCfu(dynamic cfu) {
    if (cfu is! num || cfu <= 0) return '';
    final billions = cfu / 1e9;
    if (billions >= 1) {
      return billions == billions.truncate()
          ? '${billions.toInt()} billion'
          : '${billions.toStringAsFixed(1)} billion';
    }
    final millions = cfu / 1e6;
    return millions == millions.truncate()
        ? '${millions.toInt()} million'
        : '${millions.toStringAsFixed(1)} million';
  }

  @override
  Widget build(BuildContext context) {
    if (probioticDetail == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    // CFU — read pre-formatted label first, fall back to numeric format.
    final preFormattedCfu = probioticDetail!.safeString('total_cfu_label');
    final billionCount = probioticDetail!['total_billion_count'];
    String totalCfuLabel = preFormattedCfu;
    if (totalCfuLabel.isEmpty && billionCount is num && billionCount > 0) {
      totalCfuLabel = billionCount == billionCount.truncate()
          ? '${billionCount.toInt()} billion CFU'
          : '${billionCount.toStringAsFixed(1)} billion CFU';
    }

    // Strains — flatten from probiotic_blends[].strains, not the missing
    // top-level "strains" key the old code looked for.
    final strainNames = _flattenStrainNames();
    final clinicalStrains = probioticDetail!.safeMapList('clinical_strains');
    final clinicalIds = {
      for (final cs in clinicalStrains)
        if (cs['strain'] != null) cs['strain'].toString().toLowerCase(),
    };

    // Survivability — boolean flag drives the chip; reason is the detail.
    final hasSurvivability = probioticDetail!.safeBool(
      'has_survivability_coating',
    );
    final survivabilityReason = probioticDetail!.safeString(
      'survivability_reason',
    );
    final survivabilityLabel = hasSurvivability
        ? (survivabilityReason.isNotEmpty
              ? _humanizeSurvivability(survivabilityReason)
              : 'Yes')
        : '';

    final prebioticPresent = probioticDetail!.safeBool('prebiotic_present');
    final hasPostbioticStrains = probioticDetail!.safeBool(
      'has_postbiotic_strains',
    );

    if (strainNames.isEmpty && totalCfuLabel.isEmpty) {
      return const SizedBox.shrink();
    }

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
          // Summary chip row.
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              if (totalCfuLabel.isNotEmpty)
                _InfoChip(label: 'CFU', value: totalCfuLabel),
              if (strainNames.isNotEmpty)
                _InfoChip(label: 'Strains', value: '${strainNames.length}'),
              if (clinicalStrains.isNotEmpty)
                _InfoChip(
                  label: 'Clinically studied',
                  value: '${clinicalStrains.length}',
                ),
              if (prebioticPresent)
                const _InfoChip(label: 'Prebiotic', value: 'Yes'),
              if (hasPostbioticStrains)
                const _InfoChip(label: 'Postbiotic', value: 'Yes'),
              if (hasSurvivability)
                _InfoChip(label: 'Survivability', value: survivabilityLabel),
            ],
          ),
          // Per-strain rows. Prefer clinical_strains[] when present —
          // those carry per-strain cfu_per_day + evidence_level + is_inactivated.
          // Falls back to flat strain name list when clinical metadata is absent.
          if (clinicalStrains.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space12),
            ...clinicalStrains.take(8).map((cs) {
              final name = cs['strain']?.toString() ?? '';
              final cfuLabel = _formatStrainCfu(cs['cfu_per_day']);
              final evidence = cs['evidence_level']?.toString() ?? '';
              final isInactivated = cs['is_inactivated'] == true;
              return _StrainRow(
                name: name,
                cfuLabel: cfuLabel,
                evidence: evidence,
                isInactivated: isInactivated,
                isClinical: true,
              );
            }),
          ] else if (strainNames.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space12),
            ...strainNames.take(8).map((name) {
              final isClinical = clinicalIds.contains(name.toLowerCase());
              return _StrainRow(
                name: name,
                cfuLabel: '',
                evidence: '',
                isInactivated: false,
                isClinical: isClinical,
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// Map the enricher's survivability_reason slug ("canonical_delivery_form",
/// "biotract", "spore-based") to a short, user-readable chip label.
String _humanizeSurvivability(String reason) {
  switch (reason) {
    case 'canonical_delivery_form':
      return 'Coated';
    case 'spore-based':
    case 'spore-forming':
    case 'spore forming':
      return 'Spore';
    case 'microencapsulated':
      return 'Encapsulated';
    case 'enteric coated':
    case 'enteric-coated':
    case 'enteric coating':
      return 'Enteric';
    case 'delayed release':
    case 'delayed-release':
      return 'Delayed';
    default:
      // Fall back to first 12 chars title-cased — keeps unknown branded
      // markers (BIO-tract, LiveBac) visible without code changes.
      final clean = reason.split(RegExp(r'[\s_-]+')).join(' ');
      return clean.isEmpty
          ? 'Yes'
          : clean[0].toUpperCase() + clean.substring(1);
  }
}

class _StrainRow extends StatelessWidget {
  final String name;
  final String cfuLabel;
  final String evidence;
  final bool isInactivated;
  final bool isClinical;
  const _StrainRow({
    required this.name,
    required this.cfuLabel,
    required this.evidence,
    required this.isInactivated,
    required this.isClinical,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            isClinical ? Icons.verified_outlined : Icons.circle,
            size: isClinical ? 14 : 6,
            color: isClinical ? AppTheme.severitySafe : scheme.onSurfaceVariant,
          ),
          SizedBox(width: isClinical ? 6 : 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: isClinical ? FontWeight.w600 : FontWeight.w400,
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurface,
                ),
                children: [
                  TextSpan(text: name),
                  if (isInactivated)
                    TextSpan(
                      text: '  · postbiotic',
                      style: TextStyle(
                        fontStyle: FontStyle.normal,
                        fontWeight: FontWeight.w400,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (!isInactivated && evidence.isNotEmpty)
                    TextSpan(
                      text: '  · $evidence evidence',
                      style: TextStyle(
                        fontStyle: FontStyle.normal,
                        fontWeight: FontWeight.w400,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (cfuLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                cfuLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
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
