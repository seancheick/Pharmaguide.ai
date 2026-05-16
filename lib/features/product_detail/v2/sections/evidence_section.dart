// Phase 11.7e — Evidence section adapter (S11).
//
// V2 mirror of production's `EvidenceDetailSection`
// (lib/features/product_detail/widgets/pipeline_sections/
// evidence_detail_section.dart).
//
// Production reads `evidence_data` blob:
//   match_count          int    — total clinical_matches count
//   clinical_matches[]   list   — {ingredient, pmids[], evidence_level}
//   unsubstantiated_claims[]    — flagged marketing claims (deferred)
//
// Pure helpers `evidenceTier`, `evidenceTotalStudies`,
// `evidenceHasMetaQuality` are imported verbatim from production —
// no logic duplication.
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
import 'package:pharmaguide/features/product_detail/widgets/pipeline_sections/evidence_detail_section.dart'
    show evidenceTier, evidenceTotalStudies, evidenceHasMetaQuality,
        EvidenceTier;
import 'package:url_launcher/url_launcher.dart';

/// Build the Evidence section. Returns `SizedBox.shrink()` when the
/// blob is null or contains no clinical evidence signals.
Widget buildEvidenceSection({
  required Map<String, dynamic>? evidenceData,
}) {
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
