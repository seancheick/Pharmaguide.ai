// Evidence section (Section 9).
//
// Spec: INITIATIVE_PRODUCT_TRUST_AND_IA.md, Sprint 1, T1.10.
//
// Job: surface a deterministic clinical-support tier (STRONG /
// MODERATE / LIMITED) plus an aggregate study count, then drill-down
// into the actual PMID-level citations on tap. NO editorial quote in
// V1 — pipeline doesn't curate them yet, so any text we wrote here
// would be unverifiable summary risk.
//
// Tier rules (Flutter-side derivation until pipeline ships a proper
// `meta_analysis` boolean):
//   STRONG    — total deduped studies ≥ 5 AND at least one match
//               carries a meta-quality evidence_level
//               ('strong' / 'established' / 'high').
//   MODERATE  — 3 to 4 studies, OR 5+ studies without any
//               meta-quality match.
//   LIMITED   — fewer than 3 studies (any quality).
//
// Acceptance per spec:
//   - Tier label matches actual evidence count
//   - PMIDs link out to PubMed
//   - No editorial quote in V1

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/extensions/json_helpers.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';
import 'package:url_launcher/url_launcher.dart';

/// Aggregate clinical-support tier label.
enum EvidenceTier {
  /// ≥5 deduped studies AND at least one meta-quality match.
  strong(label: 'STRONG', color: AppTheme.evidenceStrong),

  /// 3-4 studies OR 5+ studies without a meta-quality match.
  moderate(label: 'MODERATE', color: AppTheme.evidenceGood),

  /// <3 studies of any quality.
  limited(label: 'LIMITED', color: AppTheme.evidenceTheoretical);

  final String label;
  final Color color;

  const EvidenceTier({required this.label, required this.color});
}

/// Lowercase keys that the pipeline uses to flag a meta-quality
/// match. `'high'` is included for forward-compatibility with the
/// scoring-pipeline's pillar levels.
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

/// Compute the aggregate clinical-support tier from the deduped
/// study count + meta-quality flag.
EvidenceTier evidenceTier(List<Map<String, dynamic>> matches) {
  final studies = evidenceTotalStudies(matches);
  if (studies < 3) return EvidenceTier.limited;
  final meta = evidenceHasMetaQuality(matches);
  if (studies >= 5 && meta) return EvidenceTier.strong;
  return EvidenceTier.moderate;
}

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
    final unsubstantiated =
        evidenceData!.safeStringList('unsubstantiated_claims');

    if (matchCount == 0 && clinicalMatches.isEmpty) {
      return const SizedBox.shrink();
    }

    final tier = evidenceTier(clinicalMatches);
    final totalStudies = evidenceTotalStudies(clinicalMatches);
    final hasMeta = evidenceHasMetaQuality(clinicalMatches);

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: section title + match-count chip (existing).
          Row(
            children: [
              const Icon(
                Icons.science_outlined,
                size: 18,
                color: AppTheme.evidenceStrong,
              ),
              const SizedBox(width: AppTheme.space6),
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

          // T1.10 aggregate tier — "Clinical support: STRONG …" with
          // the deduped study count + meta-analysis flag below. Whole
          // row is tappable, opens a bottom sheet listing every PMID
          // grouped by ingredient.
          const SizedBox(height: AppTheme.space12),
          PGPressable(
            onTap: clinicalMatches.isEmpty
                ? null
                : () => _showAllCitations(context, clinicalMatches),
            pressedScale: 0.98,
            child: _TierBlock(
              tier: tier,
              totalStudies: totalStudies,
              hasMeta: hasMeta,
              tappable: clinicalMatches.isNotEmpty,
            ),
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
                      color: _metaQualityLevels.contains(evidence.toLowerCase())
                          ? AppTheme.severitySafe
                          : AppTheme.severityCaution,
                    ),
                    const SizedBox(width: AppTheme.space6),
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
                            '${pmids.isNotEmpty ? " · ${pmids.length} ${pmids.length == 1 ? 'study' : 'studies'}" : ""}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (pmids.isNotEmpty)
                      PGPressable(
                        onTap: () => _showCitationsForMatch(
                          context,
                          ingredient: ingredient,
                          pmids: pmids,
                        ),
                        pressedScale: 0.96,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
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
            const SizedBox(height: AppTheme.space8),
            Text(
              'Unsubstantiated claims',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppTheme.severityCaution,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.space4),
            ...unsubstantiated.map(
              (claim) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 12,
                      color: AppTheme.severityCaution,
                    ),
                    const SizedBox(width: AppTheme.space4),
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
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAllCitations(
    BuildContext context,
    List<Map<String, dynamic>> matches,
  ) {
    PGModal.bottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space12,
            AppTheme.space20,
            AppTheme.space24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Citations',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: AppTheme.space12),
              for (final match in matches) ...[
                _CitationGroup(
                  ingredient: match['ingredient']?.toString() ?? '',
                  pmids: match.safeStringList('pmids'),
                ),
                const SizedBox(height: AppTheme.space12),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showCitationsForMatch(
    BuildContext context, {
    required String ingredient,
    required List<String> pmids,
  }) {
    PGModal.bottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space20,
            AppTheme.space12,
            AppTheme.space20,
            AppTheme.space24,
          ),
          child: _CitationGroup(ingredient: ingredient, pmids: pmids),
        );
      },
    );
  }
}

/// Tier banner — "Clinical support: STRONG · 7 studies · meta-analysis"
/// with the tier color tinting the chip border.
class _TierBlock extends StatelessWidget {
  final EvidenceTier tier;
  final int totalStudies;
  final bool hasMeta;
  final bool tappable;

  const _TierBlock({
    required this.tier,
    required this.totalStudies,
    required this.hasMeta,
    required this.tappable,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subline = StringBuffer()
      ..write(
        '$totalStudies ${totalStudies == 1 ? 'study' : 'studies'} reviewed',
      );
    if (hasMeta) subline.write(' · meta-analysis available');

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space12,
        vertical: AppTheme.space8 + 2,
      ),
      decoration: BoxDecoration(
        color: tier.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: tier.color.withValues(alpha: 0.20),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Two separate Text widgets so the tier label is
                // independently findable in tests via `find.text()`.
                // (A single Text.rich with TextSpan children renders
                // to one Text widget whose data is the concatenation,
                // which find.text won't match against the bare label.)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'Clinical support: ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      tier.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: tier.color,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  subline.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (tappable)
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

/// Group of PMID citations under a single ingredient. Each PMID
/// renders as a tappable row that launches PubMed externally.
class _CitationGroup extends StatelessWidget {
  final String ingredient;
  final List<String> pmids;

  const _CitationGroup({required this.ingredient, required this.pmids});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (pmids.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ingredient.isNotEmpty)
          Text(
            ingredient,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        if (ingredient.isNotEmpty) const SizedBox(height: 6),
        for (final pmid in pmids)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: PGPressable(
              onTap: () => _launchPubmed(pmid),
              pressedScale: 0.97,
              child: Row(
                children: [
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'PMID: $pmid',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Numeric-PMID validator. PubMed IDs are integer-only; anything
  /// else (DOI, garbled string, accidental URL paste) lands at a 404
  /// which would surface as a new Sentry error class on launchUrl
  /// failure paths. Defensive — pipeline shouldn't ship non-numeric
  /// PMIDs but a stale catalog might.
  static final RegExp _pmidPattern = RegExp(r'^\d+$');

  Future<void> _launchPubmed(String pmid) async {
    final trimmed = pmid.trim();
    if (trimmed.isEmpty) return;
    if (!_pmidPattern.hasMatch(trimmed)) return;
    final uri = Uri.tryParse('https://pubmed.ncbi.nlm.nih.gov/$trimmed/');
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      // Platform channel can throw if the OS has no browser registered
      // (very rare on iOS/Android but happens on stripped device images
      // and in tests). Swallow — user gets no nav, but no crash either.
      // Keeps Sentry quiet.
    }
  }
}
