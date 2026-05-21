import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_review_before_use_card.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Severity tier driving warning card color + label. Reuses
/// [PGReviewTone] from PGReviewBeforeUseCard so a single severity-tone
/// vocabulary covers the Product Detail page.
typedef PGWarningSeverity = PGReviewTone;

/// Evidence-strength tier shown as a badge on each warning. Mirrors
/// production `EvidenceLevel` (lib/services/warnings/...). Caller maps
/// the production enum to this — keeps v2 widget independent.
enum PGEvidenceLevel { established, probable, moderate, limited, theoretical }

extension PGEvidenceLevelMeta on PGEvidenceLevel {
  String get label => switch (this) {
    PGEvidenceLevel.established => 'Established',
    PGEvidenceLevel.probable => 'Probable',
    PGEvidenceLevel.moderate => 'Moderate',
    PGEvidenceLevel.limited => 'Limited',
    PGEvidenceLevel.theoretical => 'Theoretical',
  };
}

/// Typed shape consumed by the v2 widget. Screen-level wiring adapts
/// production's `InteractionWarning` to this — keeps the widget pure.
class PGWarning {
  final PGWarningSeverity severity;
  final PGEvidenceLevel evidence;
  final String title;
  final String mechanism;

  /// "What to do" copy — production wraps it in a tinted block.
  final String? management;

  /// Number of supporting source URLs. Tap fires [onShowSources] in the
  /// parent card.
  final int sourceCount;

  /// Tap → opens production's citations bottom sheet.
  final VoidCallback? onShowSources;

  const PGWarning({
    required this.severity,
    required this.evidence,
    required this.title,
    required this.mechanism,
    this.management,
    this.sourceCount = 0,
    this.onShowSources,
  });
}

/// v2 mirror of `InteractionWarnings`
/// (lib/features/product_detail/widgets/interaction_warnings.dart).
///
/// **Same structure preserved verbatim:**
/// - Two sub-sections: "Applies to you" (personalized, auto-expanded)
///   + "Other precautions" (generic, collapsed by default)
/// - Within each section, warnings are sorted by severity (danger →
///   caution → safe) — caller is expected to pre-sort
/// - Each card shows: 3pt severity-tinted left strip + severity pill +
///   evidence badge + title + mechanism (collapsible) + management
///   block + sources count chip
///
/// **What changes in v2:**
/// - Surface: cream + outline + sm shadow on the section wrappers
/// - Typography: Geist Sans 500 (production w700)
/// - "Applies to you" subsection title is a v2 eyebrow + count badge,
///   matching the PGIngredientsCard / PGReviewBeforeUseCard pattern
class PGInteractionWarnings extends StatefulWidget {
  /// Profile-matched warnings — appear in the "Applies to you"
  /// section. Auto-expanded. Empty hides the section.
  final List<PGWarning> personalized;

  /// Generic precautions — appear in the "Other precautions" section.
  /// Auto-collapsed. Empty hides the section.
  final List<PGWarning> generic;

  const PGInteractionWarnings({
    super.key,
    this.personalized = const [],
    this.generic = const [],
  });

  @override
  State<PGInteractionWarnings> createState() => _PGInteractionWarningsState();
}

class _PGInteractionWarningsState extends State<PGInteractionWarnings> {
  bool _genericExpanded = false;

  @override
  Widget build(BuildContext context) {
    final hasPersonalized = widget.personalized.isNotEmpty;
    final hasGeneric = widget.generic.isNotEmpty;
    if (!hasPersonalized && !hasGeneric) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPersonalized) ...[
          _SubSectionHeader(
            eyebrow: 'Applies to you',
            count: widget.personalized.length,
            tone: V2Colors.caution,
          ),
          const SizedBox(height: V2Spacing.space8),
          for (var i = 0; i < widget.personalized.length; i++) ...[
            if (i > 0) const SizedBox(height: V2Spacing.space8),
            PGWarningCard(warning: widget.personalized[i]),
          ],
        ],
        if (hasPersonalized && hasGeneric)
          const SizedBox(height: V2Spacing.space16),
        if (hasGeneric) _buildGeneric(),
      ],
    );
  }

  Widget _buildGeneric() {
    // "Other precautions" wraps in its own outlined card so the
    // toggle header and (collapsible) warning rows read as one unit
    // belonging to interaction warnings — never to the next scroll
    // section. Mirrors the PGIngredientsCard "Other ingredients"
    // dropdown pattern (Sean's call 2026-05-15: the toggle was
    // floating above the Label Confidence card and looked
    // mis-attached).
    return Container(
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _genericExpanded = !_genericExpanded),
              child: Padding(
                padding: const EdgeInsets.all(V2Spacing.space16),
                child: Row(
                  children: [
                    Expanded(
                      child: _SubSectionHeader(
                        eyebrow: 'Other precautions',
                        count: widget.generic.length,
                        tone: V2Colors.fgMuted,
                      ),
                    ),
                    AnimatedRotation(
                      turns: _genericExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.expand_more_rounded,
                        size: 22,
                        color: V2Colors.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: V2Motion.base,
            curve: V2Motion.smooth,
            alignment: Alignment.topCenter,
            child: _genericExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      V2Spacing.space12,
                      0,
                      V2Spacing.space12,
                      V2Spacing.space12,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < widget.generic.length; i++) ...[
                          if (i > 0) const SizedBox(height: V2Spacing.space8),
                          PGWarningCard(warning: widget.generic[i]),
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _SubSectionHeader extends StatelessWidget {
  final String eyebrow;
  final int count;
  final Color tone;

  const _SubSectionHeader({
    required this.eyebrow,
    required this.count,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PGEyebrow(eyebrow, color: tone),
        const SizedBox(width: V2Spacing.space8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          ),
          child: Text(
            '$count',
            style: V2Typography.overline(color: tone).copyWith(
              fontSize: 11,
              letterSpacing: 0.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Single warning card. Mirrors `_WarningCard` from production's
/// interaction_warnings.dart — 3pt severity strip + tinted wash header
/// row (pill + evidence badge + title) + mechanism block + management
/// block + sources chip.
///
/// Mechanism is collapsible — long mechanism strings truncate to 3
/// lines with a "Show more" tap; expanded state reveals the full text.
class PGWarningCard extends StatefulWidget {
  final PGWarning warning;

  const PGWarningCard({super.key, required this.warning});

  @override
  State<PGWarningCard> createState() => _PGWarningCardState();
}

class _PGWarningCardState extends State<PGWarningCard> {
  bool _mechanismExpanded = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.warning;
    final tone = w.severity.tint;

    return Container(
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: tone),
            Expanded(
              child: Container(
                color: tone.withValues(alpha: 0.04),
                padding: const EdgeInsets.all(V2Spacing.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: severity pill + evidence badge
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _SeverityPill(severity: w.severity),
                        _EvidenceBadge(evidence: w.evidence),
                      ],
                    ),
                    const SizedBox(height: V2Spacing.space12),
                    Text(
                      w.title,
                      style: V2Typography.bodyMedium(
                        color: V2Colors.fg,
                      ).copyWith(fontSize: 16, height: 1.3),
                    ),
                    const SizedBox(height: V2Spacing.space8),
                    _Mechanism(
                      text: w.mechanism,
                      expanded: _mechanismExpanded,
                      onToggle: () => setState(
                        () => _mechanismExpanded = !_mechanismExpanded,
                      ),
                    ),
                    if (w.management != null) ...[
                      const SizedBox(height: V2Spacing.space12),
                      _ManagementBlock(text: w.management!, tone: tone),
                    ],
                    if (w.sourceCount > 0) ...[
                      const SizedBox(height: V2Spacing.space12),
                      _SourcesChip(
                        count: w.sourceCount,
                        onTap: w.onShowSources,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeverityPill extends StatelessWidget {
  final PGWarningSeverity severity;
  const _SeverityPill({required this.severity});

  String get _label => switch (severity) {
    PGReviewTone.danger => 'Contraindicated',
    PGReviewTone.caution => 'Caution',
    PGReviewTone.safe => 'Monitor',
    PGReviewTone.info => 'Informational',
  };

  @override
  Widget build(BuildContext context) {
    final color = severity.tint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: V2Typography.caption(color: color).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceBadge extends StatelessWidget {
  final PGEvidenceLevel evidence;
  const _EvidenceBadge({required this.evidence});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: V2Colors.outline,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      ),
      child: Text(
        evidence.label.toUpperCase(),
        style: V2Typography.overline(
          color: V2Colors.fgMuted,
        ).copyWith(fontSize: 10, letterSpacing: 0.4),
      ),
    );
  }
}

class _Mechanism extends StatelessWidget {
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  const _Mechanism({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  /// Production threshold — collapse mechanism strings >150 chars.
  bool get _isTruncatable => text.length > 150;

  @override
  Widget build(BuildContext context) {
    if (!_isTruncatable) {
      return Text(text, style: V2Typography.bodySm(color: V2Colors.fgMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: V2Typography.bodySm(color: V2Colors.fgMuted),
          maxLines: expanded ? null : 3,
          overflow: expanded ? null : TextOverflow.ellipsis,
        ),
        const SizedBox(height: V2Spacing.space4),
        GestureDetector(
          onTap: onToggle,
          child: Text(
            expanded ? 'Show less' : 'Show more',
            style: V2Typography.label(color: V2Colors.accent),
          ),
        ),
      ],
    );
  }
}

class _ManagementBlock extends StatelessWidget {
  final String text;
  final Color tone;
  const _ManagementBlock({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
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
          PGEyebrow('What to do', color: tone),
          const SizedBox(height: V2Spacing.space4),
          Text(text, style: V2Typography.body(color: V2Colors.fg)),
        ],
      ),
    );
  }
}

class _SourcesChip extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  const _SourcesChip({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: V2Colors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            border: Border.all(color: V2Colors.accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.menu_book_outlined,
                size: 14,
                color: V2Colors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                '$count source${count == 1 ? '' : 's'}',
                style: V2Typography.caption(
                  color: V2Colors.accent,
                ).copyWith(fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
