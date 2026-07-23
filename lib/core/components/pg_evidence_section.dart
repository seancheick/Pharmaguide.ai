import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
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
    PGEvidenceTier.strong => V2Colors.safe,
    PGEvidenceTier.moderate => V2Colors.monitor,
    PGEvidenceTier.limited => V2Colors.caution,
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

/// Header: tier label ("Clinical support: STRONG · 7 studies ·
/// meta-analysis") + tier-colored bullet. Citations list beneath —
/// each is a tappable PMID + title row that opens PubMed.
class PGEvidenceSection extends StatelessWidget {
  final PGEvidenceTier tier;
  final int totalStudies;
  final bool hasMetaAnalysis;
  final List<PGCitation> citations;
  final String title;
  final String? summaryPrefix;
  final String? helperLine;

  /// Optional factual enrichment line beneath the tier summary, e.g.
  /// "Backed by 4 human studies · ~620 participants".
  final String? subtitle;

  /// Optional muted caption at the bottom of the card, e.g. connecting
  /// the evidence to the score pillar above.
  final String? footnote;

  /// Optional extra content appended INSIDE the studies sheet, below the
  /// citations — e.g. related ingredient research (T10). Kept an opaque
  /// [Widget] so this core component never depends on feature models.
  final Widget? sheetExtra;

  const PGEvidenceSection({
    super.key,
    required this.tier,
    this.totalStudies = 0,
    this.hasMetaAnalysis = false,
    this.citations = const [],
    this.title = 'Clinical evidence',
    this.summaryPrefix,
    this.helperLine,
    this.subtitle,
    this.footnote,
    this.sheetExtra,
  });

  /// CTA label for the studies sheet. Prefers the human-study count the
  /// summary already advertises; falls back to the citation-row count
  /// (e.g. preclinical-only refs, which never count as "studies"), then
  /// to a research-only label when the sheet carries only [sheetExtra].
  String _sheetButtonLabel() {
    if (totalStudies > 0) return 'View studies ($totalStudies)';
    if (citations.isNotEmpty) return 'View sources (${citations.length})';
    return 'View related research';
  }

  void _openStudiesSheet(BuildContext context) {
    PGModal.bottomSheet<void>(
      context: context,
      builder: (_) => ConstrainedBox(
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
            if (citations.isNotEmpty) ...[
              const PGEyebrow('Sources', color: V2Colors.fgMuted),
              const SizedBox(height: V2Spacing.space8),
              for (var i = 0; i < citations.length; i++)
                _CitationRow(
                  citation: citations[i],
                  isLast: i == citations.length - 1,
                ),
            ],
            if (sheetExtra != null) ...[
              if (citations.isNotEmpty)
                const SizedBox(height: V2Spacing.space24),
              sheetExtra!,
            ],
          ],
        ),
      ),
    );
  }

  String _summaryLine() {
    final parts = <String>[];
    if (totalStudies > 0) {
      parts.add('$totalStudies stud${totalStudies == 1 ? 'y' : 'ies'}');
    }
    if (hasMetaAnalysis) parts.add('meta-analysis');
    final summary = parts.isEmpty
        ? tier.label
        : '${tier.label} · ${parts.join(' · ')}';
    final prefix = summaryPrefix?.trim() ?? '';
    return prefix.isEmpty ? summary : '$prefix: $summary';
  }

  /// **Phase 11.7h.4 — Sean 2026-05-16 helper-line copy.**
  /// Tier labels are jargon — "LIMITED" doesn't say *limited what*. A
  /// short helper line beneath the summary translates each tier into
  /// plain language so users can interpret the verdict without
  /// clinical training.
  String? _helperLine() {
    final override = helperLine?.trim();
    if (override != null && override.isNotEmpty) return override;

    switch (tier) {
      case PGEvidenceTier.strong:
        return 'High-quality human research is available.';
      case PGEvidenceTier.moderate:
        return 'Some human studies are available, but the body of '
            'evidence is still building.';
      case PGEvidenceTier.limited:
        return 'Evidence is early, sparse, or indirect.';
      case PGEvidenceTier.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (tier == PGEvidenceTier.none &&
        citations.isEmpty &&
        sheetExtra == null) {
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
          // Phase 11.7h.4 — plain-language helper beneath the tier
          // summary so "LIMITED" / "MODERATE" / "STRONG" are
          // interpretable without clinical training.
          if (_helperLine() != null) ...[
            const SizedBox(height: V2Spacing.space4),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Text(
                _helperLine()!,
                style: V2Typography.bodySm(color: V2Colors.fgMuted),
              ),
            ),
          ],
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space8),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Text(
                subtitle!,
                style: V2Typography.bodySm(color: V2Colors.fg),
              ),
            ),
          ],
          if (citations.isNotEmpty || sheetExtra != null) ...[
            const SizedBox(height: V2Spacing.space12),
            _ViewStudiesButton(
              label: _sheetButtonLabel(),
              onTap: () => _openStudiesSheet(context),
            ),
          ],
          if (footnote != null && footnote!.trim().isNotEmpty) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              footnote!,
              style: V2Typography.caption(color: V2Colors.fgMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tinted pill CTA that opens the studies/sources sheet. Mirrors the
/// score card's "How it's scored" control (≥44pt, a11y button role).
class _ViewStudiesButton extends StatelessWidget {
  const _ViewStudiesButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space12,
              vertical: V2Spacing.space8,
            ),
            decoration: BoxDecoration(
              color: V2Colors.accentTint,
              borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
              border: Border.all(
                color: V2Colors.accent.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.menu_book_outlined,
                  size: 14,
                  color: V2Colors.accent,
                ),
                const SizedBox(width: V2Spacing.space4),
                Text(
                  label,
                  style: V2Typography.caption(color: V2Colors.accent),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: V2Colors.accent,
                ),
              ],
            ),
          ),
        ),
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
