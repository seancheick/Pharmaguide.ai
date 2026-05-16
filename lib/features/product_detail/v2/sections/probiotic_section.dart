// Phase 11.7e — Probiotic section adapter (S14).
//
// V2 mirror of production's `ProbioticDetailSection`
// (lib/features/product_detail/widgets/pipeline_sections/
// probiotic_detail_section.dart).
//
// Production reads:
//   probiotic_detail.total_cfu_label / total_billion_count
//   probiotic_detail.probiotic_blends[].strains[]
//   probiotic_detail.clinical_strains[] — per-strain detail with
//     cfu_per_day + evidence_level + is_inactivated
//   probiotic_detail.has_survivability_coating + survivability_reason
//   probiotic_detail.prebiotic_present
//
// Section suppresses when both strainNames empty AND totalCfuLabel empty.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_probiotic_section.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';

/// Build the Probiotic section. Returns `SizedBox.shrink()` when the
/// blob is null or contains no probiotic signals.
Widget buildProbioticSection({
  required Map<String, dynamic>? probioticDetail,
}) {
  if (probioticDetail == null) return const SizedBox.shrink();

  // CFU label resolution — pre-formatted label preferred, fall back
  // to numeric (matches production lines 69-76).
  final preFormatted = probioticDetail.safeString('total_cfu_label');
  final billionCount = probioticDetail['total_billion_count'];
  String totalCfuLabel = preFormatted;
  if (totalCfuLabel.isEmpty && billionCount is num && billionCount > 0) {
    totalCfuLabel = billionCount == billionCount.truncate()
        ? '${billionCount.toInt()} billion CFU'
        : '${billionCount.toStringAsFixed(1)} billion CFU';
  }

  // Strains — prefer clinical_strains[] for richer per-strain data,
  // fall back to flattened probiotic_blends[].strains[].
  final clinicalStrains = probioticDetail.safeMapList('clinical_strains');
  final strainNames = <String>[];
  final clinicalByName = <String, Map<String, dynamic>>{};
  for (final cs in clinicalStrains) {
    final strain = cs['strain']?.toString().trim() ?? '';
    if (strain.isEmpty) continue;
    if (!clinicalByName.containsKey(strain)) {
      clinicalByName[strain] = Map<String, dynamic>.from(cs);
    }
  }
  // Flatten blends → strain names (matches _flattenStrainNames).
  for (final blend in probioticDetail.safeMapList('probiotic_blends')) {
    final raw = blend['strains'];
    if (raw is List) {
      for (final s in raw) {
        final name = s?.toString().trim() ?? '';
        if (name.isNotEmpty && !strainNames.contains(name)) {
          strainNames.add(name);
        }
      }
    }
  }
  // Add clinical strains that weren't in blends.
  for (final name in clinicalByName.keys) {
    if (!strainNames.contains(name)) strainNames.add(name);
  }

  if (strainNames.isEmpty && totalCfuLabel.isEmpty) {
    return const SizedBox.shrink();
  }

  // Build PGStrain list — clinical-strain enrichment when available.
  final strains = strainNames.map((name) {
    final cs = clinicalByName[name];
    return PGStrain(
      name: name,
      cfuLabel: cs == null ? '' : _formatStrainCfu(cs['cfu_per_day']),
      evidence: cs == null
          ? ''
          : (cs['evidence_level']?.toString().toUpperCase() ?? ''),
      isInactivated: cs?['is_inactivated'] == true,
      isClinical: cs != null,
    );
  }).toList(growable: false);

  // Survivability + prebiotic flags.
  final hasSurvivability =
      probioticDetail.safeBool('has_survivability_coating');
  final survivabilityReason =
      probioticDetail.safeString('survivability_reason');
  final survivabilityLabel = hasSurvivability
      ? (survivabilityReason.isNotEmpty
          ? _humanizeSurvivability(survivabilityReason)
          : null)
      : null;
  final prebioticPresent = probioticDetail.safeBool('prebiotic_present');

  return PGProbioticSection(
    totalCfuLabel: totalCfuLabel.isNotEmpty ? totalCfuLabel : null,
    totalStrainCount: strainNames.isNotEmpty ? strainNames.length : null,
    hasSurvivabilityCoating: hasSurvivability,
    survivabilityReason: survivabilityLabel,
    prebioticPresent: prebioticPresent,
    strains: strains,
  );
}

/// Verbatim port of production's `_formatStrainCfu` (line 49).
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

/// Verbatim port of production's `_humanizeSurvivability` (line 189).
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
      final clean = reason.split(RegExp(r'[\s_-]+')).join(' ');
      return clean.length > 12
          ? clean.substring(0, 12)
          : clean;
  }
}
