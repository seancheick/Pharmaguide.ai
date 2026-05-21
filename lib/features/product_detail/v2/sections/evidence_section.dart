// Evidence section adapter.
//
// Production reads `evidence_data` blob:
//   match_count          int    — total clinical_matches count
//   clinical_matches[]   list   — {ingredient, pmids[], evidence_level}
//   unsubstantiated_claims[]    — flagged marketing claims (deferred)
//
// V2 PGEvidenceSection takes:
//   tier: PGEvidenceTier (none / limited / moderate / strong)
//   totalStudies, hasMetaAnalysis
//   citations: List<PGCitation> — each PMID becomes a tappable row
//
// Section suppresses when match_count == 0 AND clinical_matches empty.
//
// Citations title: we don't have full PubMed titles in the blob, so
// the v2 row title is "PMID <pmid> · <ingredient>" — preserves verbatim
// data + makes the link discoverable. Tap opens PubMed externally.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_evidence_section.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:url_launcher/url_launcher.dart';

/// Aggregate clinical-support tier label.
enum EvidenceTier {
  /// >=5 deduped studies AND at least one meta-quality match.
  strong,

  /// 3-4 studies OR 5+ studies without a meta-quality match.
  moderate,

  /// <3 studies of any quality.
  limited,
}

const Set<String> _metaQualityLevels = {'strong', 'established', 'high'};

/// Sum the PMID count across all clinical matches, deduping by PMID
/// string so the same study appearing under two ingredients only
/// counts once.
int evidenceTotalStudies(List<Map<String, dynamic>> matches) {
  final unique = <String>{};
  for (final m in matches) {
    for (final pmid in m.safeStringList('pmids')) {
      final trimmed = pmid.trim();
      if (trimmed.isEmpty) continue;
      unique.add(trimmed);
    }
  }
  return unique.length;
}

/// True if any match carries a meta-quality evidence level.
bool evidenceHasMetaQuality(List<Map<String, dynamic>> matches) {
  for (final m in matches) {
    final level = (m['evidence_level']?.toString() ?? '').toLowerCase().trim();
    if (_metaQualityLevels.contains(level)) return true;
  }
  return false;
}

/// Compute the aggregate clinical-support tier from the deduped study
/// count and meta-quality flag.
EvidenceTier evidenceTier(List<Map<String, dynamic>> matches) {
  final studies = evidenceTotalStudies(matches);
  if (studies < 3) return EvidenceTier.limited;
  final meta = evidenceHasMetaQuality(matches);
  if (studies >= 5 && meta) return EvidenceTier.strong;
  return EvidenceTier.moderate;
}

/// Build the Evidence section. Returns `SizedBox.shrink()` when the
/// blob is null or contains no clinical evidence signals.
Widget buildEvidenceSection({required Map<String, dynamic>? evidenceData}) {
  if (evidenceData == null) return const SizedBox.shrink();

  final matchCount = evidenceData.safeNum('match_count') ?? 0;
  final allClinicalMatches = evidenceData.safeMapList('clinical_matches');

  // Filter out PMID-less rows — pipeline can ship clinical_matches
  // tagged with evidence_level but no PMIDs. Production hides these
  // (matches production lines 109-111).
  final clinicalMatches = allClinicalMatches
      .where((m) => m.safeStringList('pmids').isNotEmpty)
      .toList(growable: false);

  if (matchCount == 0 && clinicalMatches.isEmpty) {
    return const SizedBox.shrink();
  }

  final productionTier = evidenceTier(clinicalMatches);
  final totalStudies = evidenceTotalStudies(clinicalMatches);
  final hasMeta = evidenceHasMetaQuality(clinicalMatches);

  // Map production EvidenceTier → v2 PGEvidenceTier.
  final v2Tier = _toPGEvidenceTier(productionTier);

  // Flatten clinical_matches into PGCitation rows. Each PMID gets its
  // own row with the ingredient as the title suffix. We dedupe by PMID
  // across ingredients (production lines 58-67 dedupe-by-PMID for the
  // study count; we do the same here so the citation list mirrors).
  final seenPmids = <String>{};
  final citations = <PGCitation>[];
  for (final match in clinicalMatches) {
    final ingredient = match['ingredient']?.toString().trim() ?? '';
    for (final pmid in match.safeStringList('pmids')) {
      final trimmed = pmid.trim();
      if (trimmed.isEmpty) continue;
      if (seenPmids.contains(trimmed)) continue;
      seenPmids.add(trimmed);
      citations.add(
        PGCitation(
          pmid: trimmed,
          title: ingredient.isEmpty
              ? 'PMID $trimmed'
              : 'PMID $trimmed · $ingredient',
          onTap: () => _launchPubmed(trimmed),
        ),
      );
    }
  }

  return PGEvidenceSection(
    tier: v2Tier,
    totalStudies: totalStudies,
    hasMetaAnalysis: hasMeta,
    citations: citations,
  );
}

PGEvidenceTier _toPGEvidenceTier(EvidenceTier tier) {
  switch (tier) {
    case EvidenceTier.strong:
      return PGEvidenceTier.strong;
    case EvidenceTier.moderate:
      return PGEvidenceTier.moderate;
    case EvidenceTier.limited:
      return PGEvidenceTier.limited;
  }
}

Future<void> _launchPubmed(String pmid) async {
  final uri = Uri.tryParse('https://pubmed.ncbi.nlm.nih.gov/$pmid');
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
