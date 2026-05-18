import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One pillar's data as the v2 widget consumes it.
///
/// Mirrors what production's `_ExpandableSectionBar` reads — name,
/// micro-explanation, raw score on a pillar-specific scale (max), an
/// optional sub-breakdown map for tap-to-expand explanation, and badges
/// for callouts like "Third-party tested" / "Trusted manufacturer".
class PGPillar {
  /// Display name, e.g. "Ingredient Quality" or "Transparency & Verification".
  final String label;

  /// 1-line context shown beneath the bar. Production examples:
  /// "Form, dosage, and bioavailability", "Clinical support behind
  /// ingredients", "Label clarity and independent testing".
  final String? microExplanation;

  /// Raw pillar score on its own scale (e.g. 22/25 for Ingredient Quality,
  /// 4/5 for Transparency & Verification). Null when no data.
  final double? score;

  /// Pillar's max raw score. Production: 25 / 30 / 20 / 5 for the four
  /// pillars. Drives the bar fill (`score / max`) AND the "22/25" label.
  final int max;

  /// Optional 1-line callouts rendered to the right of the bar
  /// (e.g. "Third-party tested" with verified icon).
  final List<PGPillarBadge> badges;

  /// Tap → opens production's expand-to-explain panel. Null = inert.
  final VoidCallback? onTap;

  const PGPillar({
    required this.label,
    required this.max,
    this.score,
    this.microExplanation,
    this.badges = const [],
    this.onTap,
  });
}

class PGPillarBadge {
  final IconData icon;
  final String label;
  final Color color;
  const PGPillarBadge({
    required this.icon,
    required this.label,
    required this.color,
  });
}

/// Product score breakdown surface.
///
/// Structure:
/// - 4 pillar bars (Ingredient Quality / Safety & Purity / Evidence &
///   Research / Transparency & Verification), each as a horizontal
///   bar + raw score + microExplanation + optional badges
/// - Coverage line at the bottom (production `_CoverageLine`) — 3-tier
///   confidence indicator based on `mappedCoverage` ratio
/// - Each pillar is tappable to open the explain panel (caller wires
///   the production handler)
///
/// **What changes in v2:**
/// - Surface: cream + outline + sm shadow (production uses PGCard.elevated)
/// - Typography: Geist Sans 500 for pillar labels (production w700)
/// - Bar color: driven by the production [scoreFromPillar] → ScoreTier
///   color map — same palette as PGScoreLine, no new tiers
/// - Bar: 6pt height, rounded, tinted track + tier-colored fill
class PGScoreBreakdownCard extends StatelessWidget {
  /// 4 pillars in production order. Caller composes from the pipeline
  /// blob; sequence matters because users scan top-to-bottom.
  final List<PGPillar> pillars;

  /// 0..1 — drives the coverage line at the bottom. Null hides the line.
  final double? mappedCoverage;

  /// Top-line PG Score (0..100) shown in the card title. Null omits
  /// the number.
  final int? heroScore;

  const PGScoreBreakdownCard({
    super.key,
    required this.pillars,
    this.mappedCoverage,
    this.heroScore,
  });

  @override
  Widget build(BuildContext context) {
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
          // Card title — mirrors production
          // score_breakdown_card.dart:77-84 ("Why this scored {N}").
          // Drives the user's mental anchor for the pillars below.
          Text(
            heroScore != null
                ? 'Why this scored $heroScore'
                : 'Why this scored',
            style: V2Typography.titleSm(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space4),
          Text(
            'Tap any pillar to see what drives it.',
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space16),
          for (var i = 0; i < pillars.length; i++) ...[
            if (i > 0) const SizedBox(height: V2Spacing.space12),
            _PGPillarRow(pillar: pillars[i]),
          ],
          if (mappedCoverage != null) ...[
            const SizedBox(height: V2Spacing.space16),
            const Divider(color: V2Colors.outline, height: 1, thickness: 0.5),
            const SizedBox(height: V2Spacing.space12),
            _PGCoverageLine(coverage: mappedCoverage!),
          ],
        ],
      ),
    );
  }
}

class _PGPillarRow extends StatefulWidget {
  final PGPillar pillar;
  const _PGPillarRow({required this.pillar});

  @override
  State<_PGPillarRow> createState() => _PGPillarRowState();
}

class _PGPillarRowState extends State<_PGPillarRow> {
  bool _expanded = false;

  /// **v2 deliberate departure from production's 6-tier ScoreTier.**
  ///
  /// Production maps pillar bars through the full 6-tier palette
  /// (Exceptional / Excellent / Good / Fair / Low Quality / Poor —
  /// down to deep red #DC2626 at the bottom). Sean's call: pillars are
  /// QUALITY signals, not SAFETY signals. A 3/10 transparency score
  /// isn't dangerous, it's just lower-quality — rendering it in red
  /// reads as alarm. v2 pillar bars use a 2-tone green palette only:
  ///   - ≥5/10 (≥50% of max): V2Colors.safe
  ///   - <5/10: V2Colors.monitor
  /// Both calm — "strong" vs "room to grow", never alarming.
  ///
  /// The hero PGScoreLine still uses the full 6-tier ScoreTier because
  /// that's the top-line clinical verdict. This calming applies ONLY to
  /// the diagnostic-detail pillar bars.
  Color _toneFor(double? rawScore, int max) {
    if (rawScore == null) return V2Colors.fgSubtle;
    final fraction = (rawScore / max).clamp(0.0, 1.0);
    return fraction >= 0.5 ? V2Colors.safe : V2Colors.monitor;
  }

  /// Normalize pillar raw score to a 0–10 display scale (Sean: users
  /// don't think in engineering scales of 25/30/20/5 — same number out
  /// of 10 across every pillar reads cleanly and comparably).
  int _displayScore(double rawScore, int max) {
    return (rawScore / max * 10).round().clamp(0, 10);
  }

  /// Whether this pillar has anything to reveal on tap — a micro-
  /// explanation OR at least one badge. Pillars with neither stay
  /// inert (no chevron, no tap effect).
  bool get _hasExpansion {
    final p = widget.pillar;
    return (p.microExplanation != null && p.microExplanation!.isNotEmpty) ||
        p.badges.isNotEmpty;
  }

  void _toggle() {
    if (!_hasExpansion) return;
    setState(() => _expanded = !_expanded);
    widget.pillar.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pillar;
    final score = p.score;
    final max = p.max;
    final hasScore = score != null;
    final fill = hasScore ? (score / max).clamp(0.0, 1.0) : 0.0;
    final tone = _toneFor(score, max);

    final compact = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Compact row: label + tiny chevron + score, then bar.
          // microExplanation + badges are hidden behind tap-to-expand
          // (Sean: "more compact than that because before I used to tap
          // each section to open and read what's in it").
          // Layout fix (Sean 2026-05-15): Flexible+Spacer was splitting
          // leftover horizontal space between the label and the score,
          // which forced longer labels ("Evidence & Research", "Transparency
          // & Verification") to wrap unnecessarily AND shifted the chevron
          // mid-row. Expanded gives the label all remaining space so the
          // score sits flush at the right edge for every pillar.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.label,
                        style: V2Typography.bodyMedium(color: V2Colors.fg),
                      ),
                    ),
                    if (_hasExpansion) ...[
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: V2Colors.fgMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: V2Spacing.space8),
              if (hasScore)
                Text(
                  '${_displayScore(score, max)}/10',
                  style: V2Typography.monoData(color: tone),
                )
              else
                Text(
                  'No data',
                  style: V2Typography.caption(color: V2Colors.fgSubtle),
                ),
            ],
          ),
          const SizedBox(height: V2Spacing.space8),
          ClipRRect(
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: V2Colors.outline.withValues(alpha: 0.45)),
                  FractionallySizedBox(
                    widthFactor: fill,
                    child: Container(color: tone),
                  ),
                ],
              ),
            ),
          ),
          // Expanded reveal — microExplanation + badges. AnimatedCrossFade
          // matches production's _ExpandableSectionBar pattern.
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeOutCubic,
            crossFadeState: _expanded && _hasExpansion
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: V2Spacing.space8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.microExplanation != null) ...[
                    Text(
                      p.microExplanation!,
                      style: V2Typography.bodySm(color: V2Colors.fgMuted),
                    ),
                  ],
                  if (p.badges.isNotEmpty) ...[
                    const SizedBox(height: V2Spacing.space8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final b in p.badges) _PillarBadgeChip(badge: b),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (!_hasExpansion) return compact;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: compact,
      ),
    );
  }
}

class _PillarBadgeChip extends StatelessWidget {
  final PGPillarBadge badge;
  const _PillarBadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, size: 12, color: badge.color),
          const SizedBox(width: 4),
          Text(
            badge.label,
            style: V2Typography.caption(color: badge.color).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// v2 mirror of `_CoverageLine` (score_breakdown_card.dart:619). Same
/// 3-tier thresholds: ≥0.7 high-confidence, ≥0.3 partial,
/// else limited. Same locked
/// descriptor copy.
class _PGCoverageLine extends StatelessWidget {
  final double coverage;
  const _PGCoverageLine({required this.coverage});

  ({Color tone, String label}) _tierFor(double c) {
    if (c >= 0.7) {
      return (
        tone: V2Colors.safe,
        label: 'Most ingredients in our database — high-confidence score',
      );
    }
    if (c >= 0.3) {
      return (
        tone: V2Colors.caution,
        label: 'Some ingredients aren\'t in our database — partial coverage',
      );
    }
    return (
      tone: V2Colors.fgSubtle,
      label: 'Limited data — only part of this product is in our database',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tier = _tierFor(coverage);
    final percent = (coverage.clamp(0.0, 1.0) * 100).round();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: tier.tone, shape: BoxShape.circle),
        ),
        const SizedBox(width: V2Spacing.space8),
        Expanded(
          child: Text(
            tier.label,
            style: V2Typography.caption(color: V2Colors.fgMuted),
            maxLines: 2,
          ),
        ),
        const SizedBox(width: V2Spacing.space8),
        Text('$percent%', style: V2Typography.monoData(color: tier.tone)),
      ],
    );
  }
}
