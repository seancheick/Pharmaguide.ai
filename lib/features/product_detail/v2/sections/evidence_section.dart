// Evidence section adapter.
//
// Production reads `evidence_data` blob:
//   match_count          int    — total clinical_matches count
//   clinical_matches[]   list   — {ingredient, standard_name, study_name,
//                                  evidence_level, study_type, study_id,
//                                  id (mirrors study_id), plus optional
//                                  rich fields: references_structured[],
//                                  total_enrollment, published_rct_count,
//                                  published_meta_review_count, ...}
//
// MATCH-LEVEL DEDUPE (verified pipeline bug, dsld_id 315678): the
// pipeline emits both an elemental row ('Magnesium') and a compound
// row ('Magnesium Glycinate') for one nutrient, and the SAME study can
// match via both — clinical_matches then carries the same study twice
// under two ingredient names. All tier / count / enrollment / citation
// computation runs on matches deduped by study identity (study_id,
// falling back to id) so one study never counts twice and its
// enrollment sums once. Citations were already PMID-deduped; this
// extends the dedupe to the match level.
//   unsubstantiated_claims[]    — flagged marketing claims (deferred)
//
// `references_structured` entries: {type, authority, pmid, doi, title,
// citation, url}. There is NO `pmids` field on a match — citations come
// exclusively from references_structured.
//
// evidence_level vocabulary (pipeline-verified):
//   'branded-rct'      — the product's own formulation was RCT-tested
//   'product-human'    — human studies on the product itself
//   'strain-clinical'  — clinical evidence on the specific strain
//   'ingredient-human' — human studies on the ingredient
//   'preclinical'      — animal / in-vitro only
//   'reference'        — citation-only support
//
// Tier mapping: branded-rct / product-human -> strong; ingredient-human /
// strain-clinical -> moderate unless the match itself is high-grade human
// evidence (systematic review / meta-analysis), which also displays as strong.
// The deduped PMID count is a secondary display signal only — it never
// downgrades a tier earned by evidence_level.
//
// Section suppresses when clinical_matches is empty — including the
// malformed case where match_count > 0 but no matches parsed (never
// render a tier badge from nothing).

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_evidence_section.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/utils/pubmed_launcher.dart';

/// Aggregate clinical-support tier label.
enum EvidenceTier {
  /// At least one match at product-level human evidence
  /// (branded-rct / product-human).
  strong,

  /// At least one match at ingredient/strain-level human evidence
  /// (ingredient-human / strain-clinical).
  moderate,

  /// Only preclinical / reference matches, or no matches.
  limited,
}

const Set<String> _strongLevels = {'branded-rct', 'product-human'};
const Set<String> _moderateLevels = {'ingredient-human', 'strain-clinical'};

/// Max citation rows rendered — the blob can carry dozens of structured
/// references; the section shows the first few, deduped by PMID.
const int _maxCitations = 5;

/// Dedupe clinical matches by study identity (`study_id`, falling back
/// to `id`). The pipeline's dual elemental/compound row emission can
/// match the same study via both ingredient rows; keep the first
/// occurrence so tier, study counts, enrollment sums, and citation rows
/// each see one match per study. Matches with no identity field are
/// kept (conservative — never silently drop evidence).
List<Map<String, dynamic>> dedupeClinicalMatches(
  List<Map<String, dynamic>> matches,
) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final m in matches) {
    var identity = m['study_id']?.toString().trim() ?? '';
    if (identity.isEmpty) identity = m['id']?.toString().trim() ?? '';
    if (identity.isNotEmpty && !seen.add(identity)) continue;
    out.add(m);
  }
  return out;
}

String _level(Map<String, dynamic> m) =>
    (m['evidence_level']?.toString() ?? '').toLowerCase().trim();

/// True when the match's evidence_level is human-grade (strong ∪
/// moderate sets). Preclinical / reference matches still inform the
/// tier (as 'limited') but must never feed "human studies" counts.
bool _isHumanLevel(Map<String, dynamic> m) {
  final level = _level(m);
  return _strongLevels.contains(level) || _moderateLevels.contains(level);
}

bool _hasMetaAnalysisSignal(Map<String, dynamic> m) {
  if ((m.safeNum('published_meta_review_count') ?? 0) > 0) return true;

  final studyType = (m['study_type']?.toString() ?? '').toLowerCase().trim();
  if (studyType.contains('meta') || studyType.contains('systematic')) {
    return true;
  }

  final published = m['published_studies'];
  if (published is Iterable) {
    for (final item in published) {
      final text = item.toString().toLowerCase();
      if (text.contains('meta') || text.contains('systematic')) return true;
    }
  }

  return false;
}

bool _isStrongHumanMatch(Map<String, dynamic> m) {
  final level = _level(m);
  if (_strongLevels.contains(level)) return true;
  return _moderateLevels.contains(level) && _hasMetaAnalysisSignal(m);
}

/// True when any match is RCT-tested on this product's own formulation.
bool evidenceHasBrandedRct(List<Map<String, dynamic>> matches) =>
    matches.any((m) => _level(m) == 'branded-rct');

/// Sum the deduped PMID count across HUMAN-grade matches' structured
/// references (strong ∪ moderate evidence_level sets), so the same study
/// appearing under two ingredients only counts once. Preclinical /
/// reference matches are excluded — this count feeds "human studies"
/// copy and must never include animal or citation-only work.
int evidenceTotalStudies(List<Map<String, dynamic>> matches) {
  final unique = <String>{};
  for (final m in matches) {
    if (!_isHumanLevel(m)) continue;
    for (final ref in m.safeMapList('references_structured')) {
      final pmid = ref['pmid']?.toString().trim() ?? '';
      if (pmid.isEmpty) continue;
      unique.add(pmid);
    }
  }
  return unique.length;
}

/// True if any match carries published meta-analyses / reviews.
bool evidenceHasMetaQuality(List<Map<String, dynamic>> matches) {
  for (final m in matches) {
    if (_hasMetaAnalysisSignal(m)) return true;
  }
  return false;
}

/// Sum of reported trial enrollment across HUMAN-grade matches only
/// (0 when absent). Preclinical / reference enrollment never feeds the
/// "~X participants" copy.
int evidenceTotalEnrollment(List<Map<String, dynamic>> matches) {
  var total = 0;
  for (final m in matches) {
    if (!_isHumanLevel(m)) continue;
    total += (m.safeNum('total_enrollment') ?? 0).toInt();
  }
  return total;
}

/// Compute the aggregate clinical-support tier from the evidence_level
/// vocabulary. Matches without references_structured still inform the
/// tier — they just contribute no citation rows.
EvidenceTier evidenceTier(List<Map<String, dynamic>> matches) {
  var sawModerate = false;
  for (final m in matches) {
    if (_isStrongHumanMatch(m)) return EvidenceTier.strong;
    if (_moderateLevels.contains(_level(m))) sawModerate = true;
  }
  return sawModerate ? EvidenceTier.moderate : EvidenceTier.limited;
}

/// Optional enrichment line beneath the tier summary. Calm, factual.
String? evidenceHeadline(List<Map<String, dynamic>> matches) {
  if (evidenceHasBrandedRct(matches)) {
    return "This product's formulation was clinically studied.";
  }
  // Only describe studies as "human" when human-level evidence exists —
  // preclinical/reference-only products get no enrichment line.
  if (evidenceTier(matches) == EvidenceTier.limited) return null;
  final studies = evidenceTotalStudies(matches);
  if (studies == 0) return null;
  final enrollment = evidenceTotalEnrollment(matches);
  final base = 'Backed by $studies human ${studies == 1 ? 'study' : 'studies'}';
  if (enrollment > 0) {
    return '$base · ~$enrollment participants';
  }
  return '$base.';
}

/// Ingredient-level attribution for the strongest human evidence signal.
///
/// The section's badge remains aggregate, but this line prevents a user from
/// seeing "STRONG · N studies" without knowing which ingredient earned that
/// signal. Study counts here are ingredient-specific and PMID-deduped.
String? evidenceAttributionHeadline(List<Map<String, dynamic>> matches) {
  if (evidenceHasBrandedRct(matches)) return null;

  final byIngredient = <String, List<Map<String, dynamic>>>{};
  final labels = <String, String>{};
  final order = <String, int>{};
  final deduped = dedupeClinicalMatches(matches);

  for (var i = 0; i < deduped.length; i++) {
    final match = deduped[i];
    if (!_isHumanLevel(match)) continue;

    final label = _ingredientLabel(match);
    if (label.isEmpty) continue;

    final key = label.toLowerCase();
    byIngredient.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(match);
    labels.putIfAbsent(key, () => label);
    order.putIfAbsent(key, () => i);
  }

  _IngredientEvidenceAttribution? best;
  for (final entry in byIngredient.entries) {
    final tier = evidenceTier(entry.value);
    final attribution = _IngredientEvidenceAttribution(
      label: labels[entry.key] ?? entry.key,
      tier: tier,
      studies: evidenceTotalStudies(entry.value),
      enrollment: evidenceTotalEnrollment(entry.value),
      originalOrder: order[entry.key] ?? 0,
    );
    if (best == null || attribution.isStrongerThan(best)) {
      best = attribution;
    }
  }

  if (best == null) return null;

  final tierLabel = switch (best.tier) {
    EvidenceTier.strong => 'strong',
    EvidenceTier.moderate => 'moderate',
    EvidenceTier.limited => 'limited',
  };
  if (best.studies > 0) {
    final base =
        '${best.label}: $tierLabel support · ${best.studies} '
        'human ${best.studies == 1 ? 'study' : 'studies'}';
    if (best.enrollment > 0) {
      return '$base · ~${best.enrollment} participants';
    }
    return base;
  }
  return '${best.label}: $tierLabel support';
}

String _ingredientLabel(Map<String, dynamic> match) {
  final ingredient = match['ingredient']?.toString().trim() ?? '';
  if (ingredient.isNotEmpty) return ingredient;
  return match['standard_name']?.toString().trim() ?? '';
}

/// Build the citation rows from `references_structured`, deduped by
/// PMID across matches, using the real paper title when present.
List<PGCitation> evidenceCitations(List<Map<String, dynamic>> matches) {
  final seenPmids = <String>{};
  final citations = <PGCitation>[];
  for (final match in matches) {
    final ingredient = match['ingredient']?.toString().trim() ?? '';
    for (final ref in match.safeMapList('references_structured')) {
      final pmid = ref['pmid']?.toString().trim() ?? '';
      if (pmid.isEmpty) continue;
      if (!seenPmids.add(pmid)) continue;
      final title = ref['title']?.toString().trim() ?? '';
      citations.add(
        PGCitation(
          pmid: pmid,
          title: title.isNotEmpty
              ? title
              : (ingredient.isEmpty
                    ? 'PMID $pmid'
                    : 'PMID $pmid · $ingredient'),
          onTap: () => launchPubmed(pmid),
        ),
      );
    }
  }
  return citations;
}

/// Build the Evidence section. Returns `SizedBox.shrink()` when the
/// blob is null or contains no clinical evidence signals.
Widget buildEvidenceSection({required Map<String, dynamic>? evidenceData}) {
  if (evidenceData == null) return const SizedBox.shrink();

  // Match-level dedupe BEFORE any tier/count/citation computation —
  // see header note on the dual elemental/compound row pipeline bug.
  final clinicalMatches = dedupeClinicalMatches(
    evidenceData.safeMapList('clinical_matches'),
  );

  // Suppress when nothing parsed — including the malformed case where
  // match_count > 0 but no clinical_matches survived parsing. A LIMITED
  // badge built from zero matches would be invented signal.
  if (clinicalMatches.isEmpty) {
    return const SizedBox.shrink();
  }

  final productionTier = evidenceTier(clinicalMatches);
  final totalStudies = evidenceTotalStudies(clinicalMatches);
  final hasMeta = evidenceHasMetaQuality(clinicalMatches);
  final citations = evidenceCitations(clinicalMatches);

  return PGEvidenceSection(
    tier: _toPGEvidenceTier(productionTier),
    totalStudies: totalStudies,
    hasMetaAnalysis: hasMeta,
    subtitle:
        evidenceAttributionHeadline(clinicalMatches) ??
        evidenceHeadline(clinicalMatches),
    citations: citations.take(_maxCitations).toList(growable: false),
    footnote: 'This research feeds the Evidence pillar in the score above.',
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

class _IngredientEvidenceAttribution {
  final String label;
  final EvidenceTier tier;
  final int studies;
  final int enrollment;
  final int originalOrder;

  const _IngredientEvidenceAttribution({
    required this.label,
    required this.tier,
    required this.studies,
    required this.enrollment,
    required this.originalOrder,
  });

  bool isStrongerThan(_IngredientEvidenceAttribution other) {
    final tierCmp = _tierRank(tier).compareTo(_tierRank(other.tier));
    if (tierCmp != 0) return tierCmp > 0;
    final studiesCmp = studies.compareTo(other.studies);
    if (studiesCmp != 0) return studiesCmp > 0;
    return originalOrder < other.originalOrder;
  }

  static int _tierRank(EvidenceTier tier) {
    return switch (tier) {
      EvidenceTier.strong => 3,
      EvidenceTier.moderate => 2,
      EvidenceTier.limited => 1,
    };
  }
}
