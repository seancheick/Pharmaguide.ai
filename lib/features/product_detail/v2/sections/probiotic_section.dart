// Phase 11.7e — Probiotic section adapter (S14).
//
// Probiotic section adapter.
//
// Reads:
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
  void Function(List<String> sourceUrls)? onTapSources,
}) {
  if (probioticDetail == null) return const SizedBox.shrink();

  final probioticBlends = probioticDetail.safeMapList('probiotic_blends');

  // CFU label resolution — pre-formatted label preferred, fall back
  // to numeric (matches production lines 69-76).
  final preFormatted = probioticDetail.safeString('total_cfu_label');
  final billionCount = probioticDetail['total_billion_count'];
  String totalCfuLabel = preFormatted;
  final legacyCanonicalBillion = _legacyCanonicalServingBillion(
    probioticBlends,
    reportedTotal: billionCount,
  );
  if (legacyCanonicalBillion != null) {
    totalCfuLabel = '${_compactNumber(legacyCanonicalBillion)} billion CFU';
  }
  if (totalCfuLabel.isEmpty && billionCount is num && billionCount > 0) {
    totalCfuLabel = _formatCfuCount(billionCount.toDouble() * 1e9);
  }

  // Strains — prefer clinical_strains[] for richer per-strain data,
  // fall back to flattened probiotic_blends[].strains[].
  final clinicalStrains = probioticDetail.safeMapList('clinical_strains');
  final strainNames = <String>[];
  final clinicalByName = <String, Map<String, dynamic>>{};
  final genericContainerKeys = probioticBlends
      .map((blend) => blend['name']?.toString().trim() ?? '')
      .where(_isGenericContainerName)
      .map(_normalizedIdentity)
      .toSet();
  for (final cs in clinicalStrains) {
    final strain = cs['strain']?.toString().trim() ?? '';
    if (strain.isEmpty) continue;
    if (genericContainerKeys.contains(_normalizedIdentity(strain))) continue;
    if (!clinicalByName.containsKey(strain)) {
      clinicalByName[strain] = Map<String, dynamic>.from(cs);
    }
  }
  // Flatten blends → strain names (matches _flattenStrainNames).
  for (final blend in probioticBlends) {
    final blendName = blend['name']?.toString().trim() ?? '';
    final raw = blend['strains'];
    if (raw is List) {
      for (final s in raw) {
        final name = s?.toString().trim() ?? '';
        if (_isGenericContainerEcho(blendName: blendName, strainName: name)) {
          continue;
        }
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
  final strains = strainNames
      .map((name) {
        final cs = clinicalByName[name];
        return PGStrain(
          name: name,
          cfuLabel: cs == null ? '' : _formatStrainCfu(cs['cfu_per_day']),
          supportLevel: cs?.safeString('clinical_support_level') ?? '',
          indication: cs?.safeString('indication_primary') ?? '',
          researchStatus: _researchStatus(cs),
          sourceUrls: cs?.safeStringList('source_urls') ?? const [],
          isInactivated: cs?['is_inactivated'] == true,
        );
      })
      .toList(growable: false);

  // Survivability + prebiotic flags.
  final hasSurvivability = probioticDetail.safeBool(
    'has_survivability_coating',
  );
  final survivabilityReason = probioticDetail.safeString(
    'survivability_reason',
  );
  final survivabilityLabel = hasSurvivability
      ? (survivabilityReason.isNotEmpty
            ? _humanizeSurvivability(survivabilityReason)
            : null)
      : null;
  final prebioticPresent = probioticDetail.safeBool('prebiotic_present');
  final hasPostbioticStrains = probioticDetail.safeBool(
    'has_postbiotic_strains',
  );

  return PGProbioticSection(
    totalCfuLabel: totalCfuLabel.isNotEmpty ? totalCfuLabel : null,
    totalStrainCount: strainNames.isNotEmpty ? strainNames.length : null,
    hasSurvivabilityCoating: hasSurvivability,
    survivabilityReason: survivabilityLabel,
    prebioticPresent: prebioticPresent,
    hasPostbioticStrains: hasPostbioticStrains,
    strains: strains,
    onTapSources: onTapSources,
  );
}

/// Map the pipeline's `research_match_status` onto a badge.
///
/// The producer (`enrich_supplements_v3._strain_research_semantics`) exists to
/// stop the UI from reading membership in `clinical_strains` as proof that the
/// exact strain, product, dose, and use were validated. Deleting this mapping
/// does not make the card more conservative — it drops the qualification and
/// leaves the strain listed unannotated, which claims more, not less.
///
/// `pending_review` (no clinician sign-off) and `rejected` deliberately fall
/// through to `none`, which renders "No verified strain-specific research
/// found". Do not add them to the affirmative cases.
PGProbioticResearchStatus _researchStatus(Map<String, dynamic>? row) {
  if (row == null) return PGProbioticResearchStatus.none;
  if (row.safeBool('is_blocked')) return PGProbioticResearchStatus.none;
  return switch (row.safeString('research_match_status').trim().toLowerCase()) {
    'exact_strain' => PGProbioticResearchStatus.exactStrain,
    'formula_only' => PGProbioticResearchStatus.formulaOnly,
    'species_level' => PGProbioticResearchStatus.speciesLevel,
    _ => PGProbioticResearchStatus.none,
  };
}

bool _isGenericContainerEcho({
  required String blendName,
  required String strainName,
}) {
  final normalizedBlend = _normalizedIdentity(blendName);
  if (normalizedBlend.isEmpty ||
      normalizedBlend != _normalizedIdentity(strainName)) {
    return false;
  }
  return _isGenericContainerName(normalizedBlend);
}

bool _isGenericContainerName(String value) =>
    RegExp(r'\b(blend|complex|formula)\b').hasMatch(_normalizedIdentity(value));

String _normalizedIdentity(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

/// Repairs the one known legacy producer shape where alternative serving
/// columns were summed and one generic blend header was emitted as a strain.
/// Fresh blobs carry only the canonical serving and bypass this path.
double? _legacyCanonicalServingBillion(
  List<Map<String, dynamic>> blends, {
  required Object? reportedTotal,
}) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final blend in blends) {
    final name = blend['name']?.toString().trim() ?? '';
    final key = _normalizedIdentity(name);
    if (!RegExp(r'\b(blend|complex|formula)\b').hasMatch(key)) continue;
    grouped.putIfAbsent(key, () => []).add(blend);
  }

  for (final group in grouped.values) {
    if (group.length < 2) continue;
    var hasContainerEcho = false;
    final disclosed = <double>[];
    for (final blend in group) {
      final blendName = blend['name']?.toString().trim() ?? '';
      final strains = blend['strains'];
      if (strains is List &&
          strains.any(
            (strain) => _isGenericContainerEcho(
              blendName: blendName,
              strainName: strain?.toString().trim() ?? '',
            ),
          )) {
        hasContainerEcho = true;
      }
      final rawCfu = blend['cfu_data'];
      if (rawCfu is Map) {
        final value = rawCfu['billion_count'];
        if (value is num && value > 0) disclosed.add(value.toDouble());
      }
    }
    if (!hasContainerEcho || disclosed.length < 2) continue;
    if (reportedTotal is num) {
      final sum = disclosed.fold<double>(0, (total, value) => total + value);
      if ((sum - reportedTotal.toDouble()).abs() > 0.001) continue;
    }
    return disclosed.reduce((a, b) => a > b ? a : b);
  }
  return null;
}

String _compactNumber(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _formatStrainCfu(dynamic cfu) {
  if (cfu is! num || cfu <= 0) return '';
  return _formatCfuCount(cfu.toDouble());
}

String _formatCfuCount(double count) {
  final billions = count / 1e9;
  if (billions >= 1) {
    return '${_compactNumber(billions)} billion CFU';
  }
  final millions = count / 1e6;
  if (millions >= 1) {
    return '${_compactNumber(millions)} million CFU';
  }
  final thousands = count / 1e3;
  if (thousands >= 1) {
    return '${_compactNumber(thousands)} thousand CFU';
  }
  return '${_compactNumber(count)} CFU';
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
      return clean.length > 12 ? clean.substring(0, 12) : clean;
  }
}
