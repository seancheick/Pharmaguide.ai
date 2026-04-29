import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/util/ingredient_display.dart';
import 'package:pharmaguide/core/widgets/pg_card.dart';

/// Score breakdown card — four tappable sub-section bars with expandable
/// explanations showing WHY each pillar scored the way it did.
///
/// When [sectionBreakdown] is available (from the detail blob), tapping a
/// bar expands it to show sub-scores, bonuses, penalties, and certifications.
///
/// Sprint 1 T1.4 additions:
/// - `heroScore` renders an inline continuity label
///   ("Your 82 breaks down as:") above the pillars so the user can
///   trace the hero's Quality Score number into its pillar makeup.
/// - `mappedCoverage` renders a colored coverage line below the pillars.
///   Tier-tinted by ratio: green ≥ 0.7, yellow ≥ 0.3, red below.
class ScoreBreakdownCard extends StatelessWidget {
  final double? ingredientQuality;
  final double? safetyPurity;
  final double? evidenceResearch;
  final double? brandTrust;
  final Map<String, dynamic>? sectionBreakdown;
  final bool hasThirdPartyTesting;
  final bool isTrustedManufacturer;

  /// Hero Quality Score (0..100) shown as an inline continuity label
  /// above the pillars: "Your 82 breaks down as:". Null hides the label.
  final double? heroScore;

  /// Mapped-coverage ratio (0..1) — fraction of the product's
  /// ingredients that resolved against the IQM dataset. Drives the
  /// coverage-line tier color + subtitle. Null hides the line.
  final double? mappedCoverage;

  const ScoreBreakdownCard({
    super.key,
    this.ingredientQuality,
    this.safetyPurity,
    this.evidenceResearch,
    this.brandTrust,
    this.sectionBreakdown,
    this.hasThirdPartyTesting = false,
    this.isTrustedManufacturer = false,
    this.heroScore,
    this.mappedCoverage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PGCard(
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                // Spec §3 trust framing — was "Score breakdown" (V0
                // score-first language). 2026-04-29 dev review caught
                // the copy drift; changed to match the IA spec which
                // calls Section 3 "Product Quality".
                'Product Quality',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.15,
                ),
              ),
              if (sectionBreakdown != null) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.touch_app_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
          if (sectionBreakdown != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Tap each section to see why',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          // T1.4 continuity label — links the hero's Quality Score
          // back to its pillar makeup so users can trace the number
          // they saw at the top into its components down here.
          if (heroScore != null) ...[
            const SizedBox(height: AppTheme.space8),
            Text(
              'Your ${heroScore!.round()} breaks down as:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: AppTheme.space16),
          _ExpandableSectionBar(
            label: 'Ingredient quality',
            score: ingredientQuality,
            max: 25,
            subData:
                sectionBreakdown?['ingredient_quality']
                    as Map<String, dynamic>?,
            explainFn: _explainIngredientQuality,
          ),
          const SizedBox(height: AppTheme.space12),
          _ExpandableSectionBar(
            label: 'Safety & purity',
            score: safetyPurity,
            max: 30,
            subData:
                sectionBreakdown?['safety_purity'] as Map<String, dynamic>?,
            badges: [
              if (hasThirdPartyTesting)
                const _ExplainBadge(
                  icon: Icons.verified_outlined,
                  label: 'Third-party tested',
                  color: AppTheme.severitySafe,
                ),
            ],
            explainFn: _explainSafetyPurity,
          ),
          const SizedBox(height: AppTheme.space12),
          _ExpandableSectionBar(
            label: 'Evidence & research',
            score: evidenceResearch,
            max: 20,
            subData:
                sectionBreakdown?['evidence_research'] as Map<String, dynamic>?,
            explainFn: _explainEvidence,
          ),
          const SizedBox(height: AppTheme.space12),
          _ExpandableSectionBar(
            label: 'Brand trust',
            score: brandTrust,
            max: 5,
            subData: sectionBreakdown?['brand_trust'] as Map<String, dynamic>?,
            badges: [
              if (isTrustedManufacturer)
                const _ExplainBadge(
                  icon: Icons.factory_outlined,
                  label: 'Trusted manufacturer',
                  color: AppTheme.severitySafe,
                ),
            ],
            explainFn: _explainBrandTrust,
          ),
          // T1.4 coverage line — colored badge by ratio + descriptor
          // subtitle. Lives below the pillars so users see how
          // confidently the score above was computed.
          if (mappedCoverage != null) ...[
            const SizedBox(height: AppTheme.space16),
            _CoverageLine(coverage: mappedCoverage!),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Per-pillar explanation builders — parse sub-scores from section_breakdown
  // ---------------------------------------------------------------------------

  static List<_ExplainLine> _explainIngredientQuality(
    Map<String, dynamic>? sub,
  ) {
    if (sub == null) return [];
    final lines = <_ExplainLine>[];
    final subs = sub['sub'] as Map<String, dynamic>? ?? {};

    _addSubScore(lines, subs, 'B1_dose_accuracy', 'Dose accuracy');
    _addSubScore(lines, subs, 'B2_bioavailability', 'Bioavailable forms');
    _addSubScore(lines, subs, 'B3_form_quality', 'Form quality');
    _addSubScore(lines, subs, 'B4_allergen_bonus', 'No allergens bonus');

    if (lines.isEmpty) {
      final score = sub['score'];
      final max = sub['max'];
      if (score is num && max is num && max != 0) {
        final fraction = score / max;
        lines.add(
          _ExplainLine(
            text: fraction >= 0.7
                ? 'Good ingredient forms and dosing'
                : fraction >= 0.4
                ? 'Some forms could be more bioavailable'
                : 'Forms and doses need improvement',
            isPositive: fraction >= 0.5,
          ),
        );
      }
    }
    return lines;
  }

  static List<_ExplainLine> _explainSafetyPurity(Map<String, dynamic>? sub) {
    if (sub == null) return [];
    final lines = <_ExplainLine>[];
    final subs = sub['sub'] as Map<String, dynamic>? ?? {};

    _addSubScore(lines, subs, 'B5_third_party', 'Third-party testing');
    _addSubScore(lines, subs, 'B6_contaminant_risk', 'Contaminant risk');
    _addSubScore(lines, subs, 'B7_dose_safety', 'Dose safety (UL check)');

    // B7 evidence — pipeline scorer emits {nutrient, amount, ul, pct_ul,
    // penalty} per OVER-150%-UL flag. D4.3 additions on AGGREGATED flags
    // (forms of the same canonical summed before UL check): `aggregation:
    // "canonical_sum"` + `contributing_rows: [form names]` — required for
    // the teratogenicity case where 10k+10k IU Vitamin A forms individually
    // sit at 100% UL but together hit 200% UL.
    final penaltyEvidence = sub['B7_dose_safety_evidence'] as List?;
    if (penaltyEvidence != null) {
      for (final e in penaltyEvidence) {
        if (e is Map) {
          final nutrient = e['nutrient']?.toString() ?? '';
          if (nutrient.isEmpty) continue;
          final pctUlRaw = e['pct_ul'];
          final pctUl = pctUlRaw is num ? pctUlRaw.toDouble() : null;
          final amount = e['amount'];
          final ul = e['ul'];
          final isAggregated = e['aggregation'] == 'canonical_sum';
          final contributing = e['contributing_rows'];
          final pctStr = pctUl != null
              ? ' (${pctUl.toStringAsFixed(0)}% UL)'
              : '';
          final amountStr = (amount != null && ul != null)
              ? ' — $amount of $ul limit'
              : '';
          var text = '$nutrient exceeds safe upper limit$pctStr$amountStr';
          if (isAggregated && contributing is List && contributing.isNotEmpty) {
            // Surface that the flag is an aggregate across multiple forms —
            // key transparency for the teratogenicity case (user needs to
            // know that e.g. "2 forms of Vitamin A summed" triggered this).
            final formsCount = contributing.length;
            text += ' — summed across $formsCount forms';
          }
          lines.add(_ExplainLine(text: text, isPositive: false));
        }
      }
    }

    return lines;
  }

  static List<_ExplainLine> _explainEvidence(Map<String, dynamic>? sub) {
    if (sub == null) return [];
    final lines = <_ExplainLine>[];

    final matched = sub['matched_entries'];
    if (matched is num) {
      final summary = researchMatchSummary(matched.toInt());
      if (summary != null) {
        lines.add(_ExplainLine(text: summary, isPositive: true));
      }
    }

    final ingredientPoints =
        sub['ingredient_points'] as Map<String, dynamic>? ?? {};
    for (final entry in ingredientPoints.entries) {
      final pts = entry.value;
      if (pts is num && pts > 0) {
        lines.add(
          _ExplainLine(
            text:
                '${prettifyIngredientName(entry.key)} — research-backed bonus',
            isPositive: true,
          ),
        );
      }
    }

    if (lines.isEmpty) {
      lines.add(
        const _ExplainLine(
          text: 'Limited clinical evidence in our database',
          isPositive: false,
        ),
      );
    }
    return lines;
  }

  static List<_ExplainLine> _explainBrandTrust(Map<String, dynamic>? sub) {
    if (sub == null) return [];
    final lines = <_ExplainLine>[];
    final subs = sub['sub'] as Map<String, dynamic>? ?? {};

    _addSubScore(lines, subs, 'B8_trusted_mfg', 'Trusted manufacturer');
    _addSubScore(lines, subs, 'B9_transparency', 'Transparency');
    _addSubScore(lines, subs, 'B10_certifications', 'Certifications');

    if (lines.isEmpty) {
      final score = sub['score'];
      final max = sub['max'];
      if (score is num && max is num && max != 0) {
        final fraction = score / max;
        lines.add(
          _ExplainLine(
            text: fraction >= 0.6
                ? 'Established brand with good track record'
                : 'Limited brand verification data',
            isPositive: fraction >= 0.5,
          ),
        );
      }
    }
    return lines;
  }

  static void _addSubScore(
    List<_ExplainLine> lines,
    Map<String, dynamic> subs,
    String key,
    String label,
  ) {
    final value = subs[key];
    if (value is num) {
      lines.add(
        _ExplainLine(
          text: '$label: ${value.toStringAsFixed(1)} pts',
          isPositive: value > 0,
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Expandable section bar — tappable to reveal why
// ---------------------------------------------------------------------------

class _ExpandableSectionBar extends StatefulWidget {
  final String label;
  final double? score;
  final int max;
  final Map<String, dynamic>? subData;
  final List<_ExplainBadge> badges;
  final List<_ExplainLine> Function(Map<String, dynamic>?) explainFn;

  const _ExpandableSectionBar({
    required this.label,
    required this.score,
    required this.max,
    this.subData,
    this.badges = const [],
    required this.explainFn,
  });

  @override
  State<_ExpandableSectionBar> createState() => _ExpandableSectionBarState();
}

class _ExpandableSectionBarState extends State<_ExpandableSectionBar> {
  bool _expanded = false;

  static Color _colorFor(double fraction) {
    if (fraction >= 0.85) return AppTheme.scoreExceptional;
    if (fraction >= 0.70) return AppTheme.scoreExcellent;
    if (fraction >= 0.55) return AppTheme.scoreGood;
    if (fraction >= 0.40) return AppTheme.scoreFair;
    if (fraction >= 0.25) return AppTheme.scoreBelowAvg;
    return AppTheme.scoreLow;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = widget.score ?? 0.0;
    final fraction = (value / widget.max).clamp(0.0, 1.0);
    final color = _colorFor(fraction);
    final hasExplanation = widget.subData != null || widget.badges.isNotEmpty;

    return GestureDetector(
      onTap: hasExplanation
          ? () => setState(() => _expanded = !_expanded)
          : null,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (hasExplanation) ...[
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: AppMotion.fast,
                      child: Icon(
                        Icons.expand_more,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                widget.score != null
                    ? '${value.toStringAsFixed(1)}/${widget.max}'
                    : '—/${widget.max}',
                style: AppTheme.numeric(
                  theme.textTheme.labelMedium!.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),

          // Expanded explanation
          AnimatedCrossFade(
            duration: AppMotion.fast,
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildExplanation(theme, scheme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplanation(ThemeData theme, ColorScheme scheme) {
    final lines = widget.explainFn(widget.subData);
    final allItems = <Widget>[
      // Badges first
      ...widget.badges,
      // Then explanation lines
      ...lines.map(
        (line) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                line.isPositive
                    ? Icons.add_circle_outline
                    : Icons.remove_circle_outline,
                size: 13,
                color: line.isPositive
                    ? AppTheme.severitySafe
                    : AppTheme.severityCaution,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  line.text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];

    if (allItems.isEmpty) {
      return Text(
        'Detailed breakdown not available for this product.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
          fontSize: 11,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppTheme.space8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: allItems,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper types
// ---------------------------------------------------------------------------

class _ExplainLine {
  final String text;
  final bool isPositive;
  const _ExplainLine({required this.text, required this.isPositive});
}

class _ExplainBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ExplainBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// T1.4 coverage line — single row with a colored dot, percentage, and
/// short descriptor explaining how complete the IQM mapping is for the
/// scored ingredients. Tier-tinted by the same ratio thresholds used in
/// the hero's "Limited data" guard (≥0.7 great / ≥0.3 partial /
/// otherwise limited).
///
/// Pulled out of the main card body so the visual treatment can evolve
/// without churning the Column above it.
class _CoverageLine extends StatelessWidget {
  final double coverage; // 0..1
  const _CoverageLine({required this.coverage});

  /// Map a 0..1 coverage ratio to a tone + descriptor copy.
  ///
  /// The thresholds mirror the existing [_buildAllTags] / hero
  /// "Limited data" gate (`mappedCoverage < 0.3`) so the same product
  /// reads consistently across surfaces.
  ({Color tone, String label}) _tierFor(double c) {
    if (c >= 0.7) {
      return (
        tone: AppTheme.scoreExcellent,
        label: 'Most ingredients in our database — high-confidence score',
      );
    }
    if (c >= 0.3) {
      return (
        tone: AppTheme.scoreFair,
        label: 'Some ingredients aren\'t in our database — partial coverage',
      );
    }
    return (
      tone: AppTheme.insufficientData,
      label: 'Limited data — only part of this product is in our database',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Clamp defensively; pipeline could ship a >1 ratio if someone
    // miscounts mapped > total.
    final clamped = coverage.clamp(0.0, 1.0);
    final tier = _tierFor(clamped);
    final pct = (clamped * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space12,
        vertical: AppTheme.space8,
      ),
      decoration: BoxDecoration(
        color: tier.tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: tier.tone.withValues(alpha: 0.20),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Colored coverage dot — high-contrast cue, no icon noise.
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: tier.tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppTheme.space8),
          // Coverage label — "Coverage" + percent (tabular figures so
          // animating between values doesn't reflow the row).
          Text(
            'Coverage',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: tier.tone,
            ),
          ),
          const SizedBox(width: AppTheme.space8),
          Text(
            '$pct%',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: tier.tone,
            ),
          ),
          const SizedBox(width: AppTheme.space12),
          // Descriptor — flexes to fill the rest of the row, ellipsis
          // truncates on very narrow screens (the dot+pct still convey
          // the tier even if the label gets clipped).
          Expanded(
            child: Text(
              tier.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
