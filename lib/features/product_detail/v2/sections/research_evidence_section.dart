import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/models/research_pair_evidence.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/services/stack/research_pair_lookup.dart';
import 'package:url_launcher/url_launcher.dart';

@visibleForTesting
final researchEvidenceForProductProvider = FutureProvider.family
    .autoDispose<List<ResearchPairEvidence>, ResearchEvidenceRequest>((
      ref,
      request,
    ) async {
      final db = ref.watch(interactionDatabaseProvider);
      List<UserStacksLocalData> stack = const <UserStacksLocalData>[];
      try {
        stack = await ref.watch(activeStackProvider.future);
      } on Object {
        // Tier 2 evidence is informational. If stack hydration is
        // unavailable, keep broad product evidence rather than failing
        // the whole section.
      }
      return ResearchPairLookup(db).lookupForProduct(
        canonicalIds: request.canonicalIds,
        stack: stack,
        limit: request.limit,
      );
    });

class ResearchEvidenceRequest {
  final List<String> canonicalIds;
  final int limit;

  ResearchEvidenceRequest({
    required Iterable<String> canonicalIds,
    this.limit = 6,
  }) : canonicalIds = List.unmodifiable(
         canonicalIds
             .map((id) => id.trim().toLowerCase())
             .where((id) => id.isNotEmpty)
             .toSet(),
       );

  @override
  bool operator ==(Object other) {
    return other is ResearchEvidenceRequest &&
        other.limit == limit &&
        const ListEquality<String>().equals(other.canonicalIds, canonicalIds);
  }

  @override
  int get hashCode =>
      Object.hash(limit, const ListEquality<String>().hash(canonicalIds));
}

class ResearchEvidenceSection extends ConsumerWidget {
  final List<String> canonicalIds;

  const ResearchEvidenceSection({super.key, required this.canonicalIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (canonicalIds.isEmpty) return const SizedBox.shrink();

    final evidenceAsync = ref.watch(
      researchEvidenceForProductProvider(
        ResearchEvidenceRequest(canonicalIds: canonicalIds),
      ),
    );

    return evidenceAsync.maybeWhen(
      data: (evidence) {
        if (evidence.isEmpty) return const SizedBox.shrink();
        return _ResearchEvidenceCard(evidence: evidence);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _ResearchEvidenceCard extends StatelessWidget {
  final List<ResearchPairEvidence> evidence;

  const _ResearchEvidenceCard({required this.evidence});

  @override
  Widget build(BuildContext context) {
    final paperCount = evidence.fold<int>(
      0,
      (sum, row) => sum + row.paperCount,
    );
    final top = evidence.take(3).toList(growable: false);
    final topPair = evidence.first;
    final otherCount = evidence.length - 1;
    final headline = otherCount == 0
        ? '${topPair.pairLabel} in ${topPair.paperCount} published ${topPair.paperCount == 1 ? "paper" : "papers"}'
        : '${topPair.pairLabel} and $otherCount more ${otherCount == 1 ? "combination" : "combinations"} in published research';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        onTap: () => showResearchEvidenceDrawer(context, evidence),
        child: AnimatedContainer(
          duration: V2Motion.base,
          curve: V2Motion.smooth,
          decoration: BoxDecoration(
            color: V2Colors.surface,
            borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            border: Border.all(color: V2Colors.outline),
            boxShadow: V2Shadows.sm,
          ),
          padding: const EdgeInsets.all(V2Spacing.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: V2Colors.accentTint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.biotech_outlined,
                      size: 20,
                      color: V2Colors.accent,
                    ),
                  ),
                  const SizedBox(width: V2Spacing.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const PGEyebrow('Studied combinations'),
                        const SizedBox(height: V2Spacing.space4),
                        Text(
                          headline,
                          style: V2Typography.bodyMedium(color: V2Colors.fg),
                        ),
                        if (otherCount > 0) ...[
                          const SizedBox(height: V2Spacing.space4),
                          Text(
                            '$paperCount published ${paperCount == 1 ? "paper" : "papers"} across these pairs',
                            style: V2Typography.caption(
                              color: V2Colors.fgMuted,
                            ),
                          ),
                        ],
                        const SizedBox(height: V2Spacing.space4),
                        Text(
                          "Where this product's ingredients appear in research together with other substances — context, not a warning.",
                          style: V2Typography.caption(color: V2Colors.fgMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: V2Spacing.space8),
                  const Icon(
                    Icons.expand_more_rounded,
                    size: 22,
                    color: V2Colors.fgMuted,
                  ),
                ],
              ),
              const SizedBox(height: V2Spacing.space12),
              Wrap(
                spacing: V2Spacing.space8,
                runSpacing: V2Spacing.space8,
                children: [
                  for (final row in top)
                    _EvidencePill(label: row.pairLabel, count: row.paperCount),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidencePill extends StatelessWidget {
  final String label;
  final int count;

  const _EvidencePill({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space8,
        vertical: V2Spacing.space4,
      ),
      decoration: BoxDecoration(
        color: V2Colors.accentTint,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Text(
        '$label - $count',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: V2Typography.caption(color: V2Colors.accent),
      ),
    );
  }
}

@visibleForTesting
void showResearchEvidenceDrawer(
  BuildContext context,
  List<ResearchPairEvidence> evidence,
) {
  PGModal.bottomSheet<void>(
    context: context,
    builder: (_) => _ResearchEvidenceDrawer(evidence: evidence),
  );
}

class _ResearchEvidenceDrawer extends StatelessWidget {
  final List<ResearchPairEvidence> evidence;

  const _ResearchEvidenceDrawer({required this.evidence});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 640),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space16,
          0,
          V2Spacing.space16,
          V2Spacing.space24,
        ),
        shrinkWrap: true,
        children: [
          const PGEyebrow('Studied combinations'),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'PubMed co-occurrences from supp.ai',
            style: V2Typography.titleSm(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            "Where this product's ingredients and other substances appear together in published literature — context for your reading, not warnings, scores, or clinical instructions.",
            style: V2Typography.bodySm(color: V2Colors.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space16),
          for (var i = 0; i < evidence.length; i++) ...[
            if (i > 0) const SizedBox(height: V2Spacing.space16),
            _ResearchEvidenceRow(evidence: evidence[i]),
          ],
        ],
      ),
    );
  }
}

class _ResearchEvidenceRow extends StatelessWidget {
  final ResearchPairEvidence evidence;

  const _ResearchEvidenceRow({required this.evidence});

  @override
  Widget build(BuildContext context) {
    final primarySentence = evidence.topSentences.firstOrNull;
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        color: V2Colors.bg,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            evidence.pairLabel,
            style: V2Typography.bodyMedium(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space4),
          Text(
            _summary(evidence),
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
          if (primarySentence != null) ...[
            const SizedBox(height: V2Spacing.space8),
            Text(
              primarySentence.sentence,
              style: V2Typography.bodySm(color: V2Colors.fg),
            ),
          ],
          if (evidence.topPmids.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space8),
            Wrap(
              spacing: V2Spacing.space8,
              runSpacing: V2Spacing.space8,
              children: [
                for (final pmid in evidence.topPmids.take(5))
                  _PmidChip(pmid: pmid),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _summary(ResearchPairEvidence evidence) {
    final year = evidence.latestPaperYear;
    final yearText = year == null ? '' : ' - latest $year';
    return '${evidence.paperCount} papers, ${evidence.humanStudyCount} human, ${evidence.clinicalStudyCount} clinical$yearText';
  }
}

class _PmidChip extends StatelessWidget {
  final String pmid;

  const _PmidChip({required this.pmid});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      onTap: () => unawaited(_launchPubmed(pmid)),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space8,
          vertical: V2Spacing.space4,
        ),
        decoration: BoxDecoration(
          color: V2Colors.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          border: Border.all(color: V2Colors.outline),
        ),
        child: Text(
          'PMID $pmid',
          style: V2Typography.overline(color: V2Colors.accent),
        ),
      ),
    );
  }

  Future<void> _launchPubmed(String pmid) async {
    if (!RegExp(r'^\d+$').hasMatch(pmid)) return;
    final uri = Uri.parse('https://pubmed.ncbi.nlm.nih.gov/$pmid');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
