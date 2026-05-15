import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Clinical evidence tier — mirrors production `EvidenceTier`.
enum PGEvidenceTier { strong, moderate, limited, none }

extension PGEvidenceTierMeta on PGEvidenceTier {
  String get label => switch (this) {
        PGEvidenceTier.strong => 'STRONG',
        PGEvidenceTier.moderate => 'MODERATE',
        PGEvidenceTier.limited => 'LIMITED',
        PGEvidenceTier.none => 'NO DIRECT EVIDENCE',
      };

  Color get color => switch (this) {
        PGEvidenceTier.strong => AppTheme.scoreExcellent,
        PGEvidenceTier.moderate => AppTheme.scoreGood,
        PGEvidenceTier.limited => AppTheme.severityCaution,
        PGEvidenceTier.none => V2Colors.fgSubtle,
      };
}

/// One citation — typically a PubMed entry (PMID + title). Tap opens
/// the external link.
class PGCitation {
  final String pmid;
  final String title;

  /// Optional publication year ("2023").
  final String? year;

  /// External-link handler (production uses `url_launcher` to open
  /// `https://pubmed.ncbi.nlm.nih.gov/<pmid>`).
  final VoidCallback? onTap;

  const PGCitation({
    required this.pmid,
    required this.title,
    this.year,
    this.onTap,
  });
}

/// v2 mirror of `EvidenceDetailSection`
/// (lib/features/product_detail/widgets/pipeline_sections/
/// evidence_detail_section.dart).
///
/// Header: tier label ("Clinical support: STRONG · 7 studies ·
/// meta-analysis") + tier-colored bullet. Citations list beneath —
/// each is a tappable PMID + title row that opens PubMed.
class PGEvidenceSection extends StatelessWidget {
  final PGEvidenceTier tier;
  final int totalStudies;
  final bool hasMetaAnalysis;
  final List<PGCitation> citations;
  final String title;

  const PGEvidenceSection({
    super.key,
    required this.tier,
    this.totalStudies = 0,
    this.hasMetaAnalysis = false,
    this.citations = const [],
    this.title = 'Clinical evidence',
  });

  String _summaryLine() {
    final parts = <String>[];
    if (totalStudies > 0) {
      parts.add('$totalStudies stud${totalStudies == 1 ? 'y' : 'ies'}');
    }
    if (hasMetaAnalysis) parts.add('meta-analysis');
    return parts.isEmpty ? tier.label : '${tier.label} · ${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    if (tier == PGEvidenceTier.none && citations.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.titleSm(color: V2Colors.fg)),
          const SizedBox(height: V2Spacing.space12),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: tier.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: V2Spacing.space8),
              Expanded(
                child: Text(
                  _summaryLine(),
                  style: V2Typography.bodyMedium(color: tier.color),
                ),
              ),
            ],
          ),
          if (citations.isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space16),
            const Divider(
              color: V2Colors.outline,
              height: 1,
              thickness: 0.5,
            ),
            const SizedBox(height: V2Spacing.space12),
            const PGEyebrow('Sources', color: V2Colors.fgMuted),
            const SizedBox(height: V2Spacing.space8),
            for (var i = 0; i < citations.length; i++)
              _CitationRow(
                citation: citations[i],
                isLast: i == citations.length - 1,
              ),
          ],
        ],
      ),
    );
  }
}

class _CitationRow extends StatelessWidget {
  final PGCitation citation;
  final bool isLast;

  const _CitationRow({required this.citation, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: V2Spacing.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.menu_book_outlined,
            size: 14,
            color: V2Colors.accent,
          ),
          const SizedBox(width: V2Spacing.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  citation.title,
                  style: V2Typography.bodySm(color: V2Colors.fg),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  citation.year != null
                      ? 'PMID ${citation.pmid} · ${citation.year}'
                      : 'PMID ${citation.pmid}',
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                ),
              ],
            ),
          ),
          if (citation.onTap != null) ...[
            const SizedBox(width: V2Spacing.space8),
            const Icon(
              Icons.open_in_new_rounded,
              size: 14,
              color: V2Colors.fgMuted,
            ),
          ],
        ],
      ),
    );

    final wrapped = citation.onTap != null
        ? Material(
            color: Colors.transparent,
            child: InkWell(onTap: citation.onTap, child: row),
          )
        : row;

    if (isLast) return wrapped;
    return Column(
      children: [
        wrapped,
        const Divider(color: V2Colors.outline, height: 1, thickness: 0.4),
      ],
    );
  }
}
