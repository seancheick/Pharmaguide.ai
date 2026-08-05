import 'package:flutter/material.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';
import 'package:pharmaguide/core/scoring/v4_pillars.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One pipeline-backed score pillar. The app renders [reason] and [facts]
/// verbatim; it does not create supplemental scoring explanations.
class PGPillar {
  final String label;
  final double? score;
  final int max;
  final String? reason;
  final List<V4PillarFact> facts;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Compatibility input until the score-section adapter is migrated. It is
  /// never rendered independently of [reason].
  @Deprecated('Use reason')
  final String? microExplanation;

  /// Compatibility type retained until the adapter stops supplying badges.
  /// Local badges are deliberately not rendered as score rationale.
  @Deprecated('Score badges are not rendered')
  final List<PGPillarBadge> badges;

  @Deprecated('Use actionLabel and onAction')
  final VoidCallback? onTap;

  const PGPillar({
    required this.label,
    required this.max,
    this.score,
    this.reason,
    this.facts = const [],
    this.actionLabel,
    this.onAction,
    this.microExplanation,
    this.badges = const [],
    this.onTap,
  });

  String? get effectiveReason => reason ?? microExplanation;
}

@Deprecated('Score badges are no longer rendered')
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

class PGScoreAdjustment {
  final String label;
  final double delta;
  final double finalScore;

  const PGScoreAdjustment({
    required this.label,
    required this.delta,
    required this.finalScore,
  });
}

class PGScoreBreakdownCard extends StatefulWidget {
  final List<PGPillar> pillars;
  final num? heroScore;
  final PGScoreAdjustment? adjustment;
  final VoidCallback? onHowScoringWorks;

  const PGScoreBreakdownCard({
    super.key,
    required this.pillars,
    this.heroScore,
    this.adjustment,
    this.onHowScoringWorks,
  });

  static String fmtScore(num value) {
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.round().toString()
        : rounded.toStringAsFixed(1);
  }

  /// Consumer-facing product totals use the same whole-number presentation
  /// as the hero. Pillar rows keep one-decimal precision through [fmtScore].
  static String fmtTotalScore(num value) => value.round().toString();

  static String fmtSignedScore(num value) {
    final sign = value < 0
        ? '−'
        : value > 0
        ? '+'
        : '';
    return '$sign${fmtScore(value.abs())}';
  }

  static Color pillarTone(double? rawScore, num max, V2Palette palette) {
    if (rawScore == null || max <= 0) return palette.fgSubtle;
    final fraction = (rawScore / max).clamp(0.0, 1.0);
    return fraction >= 0.5 ? palette.safe : palette.monitor;
  }

  @override
  State<PGScoreBreakdownCard> createState() => _PGScoreBreakdownCardState();
}

class _PGScoreBreakdownCardState extends State<PGScoreBreakdownCard> {
  int? _expandedIndex;
  late List<({String identity, double? score, int max})> _pillarSignature;

  @override
  void initState() {
    super.initState();
    _pillarSignature = _signatureFor(widget.pillars);
    _expandedIndex = _initialExpandedIndex(widget.pillars);
  }

  @override
  void didUpdateWidget(covariant PGScoreBreakdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = _signatureFor(widget.pillars);
    if (!_sameSignature(_pillarSignature, nextSignature)) {
      _pillarSignature = nextSignature;
      _expandedIndex = _initialExpandedIndex(widget.pillars);
    }
  }

  static List<({String identity, double? score, int max})> _signatureFor(
    List<PGPillar> pillars,
  ) => [
    for (final pillar in pillars)
      (identity: pillar.label, score: pillar.score, max: pillar.max),
  ];

  static bool _sameSignature(
    List<({String identity, double? score, int max})> previous,
    List<({String identity, double? score, int max})> next,
  ) {
    if (previous.length != next.length) return false;
    for (var index = 0; index < previous.length; index++) {
      if (previous[index] != next[index]) return false;
    }
    return true;
  }

  static int? _initialExpandedIndex(List<PGPillar> pillars) {
    for (var index = 0; index < pillars.length; index++) {
      final pillar = pillars[index];
      if (!_isExactZero(pillar)) continue;
      final hasWiredAction =
          (pillar.actionLabel?.trim().isNotEmpty ?? false) &&
          pillar.onAction != null;
      final hasPipelineFact = pillar.facts.any(
        (fact) => !fact.id.startsWith('ui_'),
      );
      if (hasWiredAction || hasPipelineFact) return index;
    }
    return null;
  }

  static bool _isExactZero(PGPillar pillar) =>
      pillar.score == 0 && pillar.max > 0;

  double? get _pillarSum {
    if (widget.pillars.isEmpty) return null;
    var sum = 0.0;
    for (final pillar in widget.pillars) {
      final score = pillar.score;
      if (score == null) return null;
      sum += (score * 10).round() / 10;
    }
    return sum;
  }

  void _toggle(int index) {
    setState(() => _expandedIndex = _expandedIndex == index ? null : index);
  }

  @override
  Widget build(BuildContext context) {
    final sum = _pillarSum;
    final adjustment = widget.adjustment;
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: widget.heroScore != null
                    // Tint the number by the same tier contract as the hero
                    // score — the accessible `textColor` token (>=4.5:1 on
                    // cream), never color-alone (the tier word lives in the
                    // hero). Keep the label neutral.
                    ? Text.rich(
                        TextSpan(
                          style: V2Typography.titleSm(color: context.v2.fg),
                          children: [
                            const TextSpan(text: 'Why this scored '),
                            TextSpan(
                              text: PGScoreBreakdownCard.fmtTotalScore(
                                widget.heroScore!,
                              ),
                              style: V2Typography.titleSm(
                                color: tierForScore(
                                  widget.heroScore!.round(),
                                ).textColor(Theme.of(context).brightness),
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        'Why this scored',
                        style: V2Typography.titleSm(color: context.v2.fg),
                      ),
              ),
            ],
          ),
          const SizedBox(height: V2Spacing.space4),
          Text(
            'Six pillars, out of 100 — they add up to the score.',
            style: V2Typography.caption(color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space16),
          for (var index = 0; index < widget.pillars.length; index++) ...[
            if (index > 0) const SizedBox(height: V2Spacing.space12),
            _PGPillarRow(
              pillar: widget.pillars[index],
              isExpanded: _expandedIndex == index,
              onToggle: () => _toggle(index),
            ),
          ],
          if (sum != null && widget.adjustment == null) ...[
            const SizedBox(height: V2Spacing.space12),
            Divider(color: context.v2.outline, height: 1, thickness: 0.5),
            const SizedBox(height: V2Spacing.space8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '= ${PGScoreBreakdownCard.fmtTotalScore(sum)}/100',
                style: V2Typography.monoData(color: context.v2.fg),
              ),
            ),
          ],
          if (sum != null && adjustment != null) ...[
            const SizedBox(height: V2Spacing.space12),
            Divider(color: context.v2.outline, height: 1, thickness: 0.5),
            const SizedBox(height: V2Spacing.space8),
            _ScoreMathRow(
              label: 'Pillar subtotal',
              value: '${PGScoreBreakdownCard.fmtTotalScore(sum)}/100',
            ),
            const SizedBox(height: V2Spacing.space8),
            _ScoreMathRow(
              label: adjustment.label,
              value: PGScoreBreakdownCard.fmtSignedScore(adjustment.delta),
            ),
            const SizedBox(height: V2Spacing.space8),
            Divider(color: context.v2.outline, height: 1, thickness: 0.5),
            const SizedBox(height: V2Spacing.space8),
            _ScoreMathRow(
              label: 'Final score',
              value:
                  '${PGScoreBreakdownCard.fmtTotalScore(adjustment.finalScore)}/100',
              emphasized: true,
            ),
          ],
          if (widget.onHowScoringWorks != null) ...[
            const SizedBox(height: V2Spacing.space8),
            _HowPGScoreWorksButton(onTap: widget.onHowScoringWorks!),
          ],
        ],
      ),
    );
  }
}

class _ScoreMathRow extends StatelessWidget {
  const _ScoreMathRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? V2Typography.bodyMedium(color: context.v2.fg)
        : V2Typography.bodySm(color: context.v2.fgMuted);
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: V2Typography.monoData(color: context.v2.fg)),
      ],
    );
  }
}

/// Full-width explanation row after the score evidence, where it reads as the
/// next step rather than competing with the score-card headline.
class _HowPGScoreWorksButton extends StatelessWidget {
  const _HowPGScoreWorksButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'How PG Score works',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space12,
              vertical: V2Spacing.space8,
            ),
            decoration: BoxDecoration(
              color: context.v2.accentTint,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: context.v2.accent,
                ),
                const SizedBox(width: V2Spacing.space8),
                Expanded(
                  child: Text(
                    'How PG Score works',
                    style: V2Typography.bodyMedium(color: context.v2.accent),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: context.v2.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PGPillarRow extends StatelessWidget {
  final PGPillar pillar;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _PGPillarRow({
    required this.pillar,
    required this.isExpanded,
    required this.onToggle,
  });

  bool get _isExactZero => pillar.score == 0 && pillar.max > 0;

  bool get _hasReason => pillar.effectiveReason?.trim().isNotEmpty ?? false;

  String? get _inlineZeroReason {
    final reason = pillar.reason;
    return _isExactZero && (reason?.trim().isNotEmpty ?? false) ? reason : null;
  }

  bool get _hasAction =>
      (pillar.actionLabel?.trim().isNotEmpty ?? false) &&
      pillar.onAction != null;

  bool get _hasDetails =>
      (!_isExactZero && _hasReason) || pillar.facts.isNotEmpty || _hasAction;

  String _semanticsLabel({
    required bool hasScore,
    required String statusLabel,
  }) {
    final parts = <String>[
      pillar.label,
      if (hasScore)
        '${PGScoreBreakdownCard.fmtScore(pillar.score!)}/${pillar.max}'
      else
        'No data',
      if (hasScore) statusLabel,
      if (_inlineZeroReason != null) _inlineZeroReason!.trim(),
    ];
    final label = parts.join('. ');
    return label.endsWith('.') || label.endsWith('!') || label.endsWith('?')
        ? label
        : '$label.';
  }

  @override
  Widget build(BuildContext context) {
    final score = pillar.score;
    final hasScore = score != null;
    final fill = hasScore && pillar.max > 0
        ? (score / pillar.max).clamp(0.0, 1.0)
        : 0.0;
    final tone = PGScoreBreakdownCard.pillarTone(score, pillar.max, context.v2);
    final status = statusForPillar(score, pillar.max);
    final statusLabel = v4PillarStatusLabel(status);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _hasDetails ? onToggle : null,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                label: _semanticsLabel(
                  hasScore: hasScore,
                  statusLabel: statusLabel,
                ),
                button: _hasDetails,
                expanded: _hasDetails ? isExpanded : null,
                onTap: _hasDetails ? onToggle : null,
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  pillar.label,
                                  style: V2Typography.bodyMedium(
                                    color: context.v2.fg,
                                  ),
                                ),
                              ),
                              if (_hasDetails) ...[
                                const SizedBox(width: 4),
                                AnimatedRotation(
                                  turns: isExpanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 180),
                                  child: const Icon(
                                    Icons.expand_more_rounded,
                                    size: 16,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: V2Spacing.space8),
                        if (hasScore)
                          Text(
                            '${PGScoreBreakdownCard.fmtScore(score)}/${pillar.max}',
                            style: V2Typography.monoData(color: tone),
                          )
                        else
                          Text(
                            'No data',
                            style: V2Typography.caption(
                              color: context.v2.fgSubtle,
                            ),
                          ),
                      ],
                    ),
                    if (hasScore) ...[
                      const SizedBox(height: V2Spacing.space4),
                      Text(
                        statusLabel,
                        style: V2Typography.caption(color: tone),
                      ),
                    ],
                    if (_inlineZeroReason != null) ...[
                      const SizedBox(height: V2Spacing.space4),
                      Text(
                        _inlineZeroReason!,
                        style: V2Typography.bodySm(color: context.v2.fgMuted),
                      ),
                    ],
                    const SizedBox(height: V2Spacing.space8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
                      child: SizedBox(
                        height: 6,
                        child: Stack(
                          children: [
                            Container(
                              color: context.v2.outline.withValues(alpha: 0.45),
                            ),
                            FractionallySizedBox(
                              widthFactor: fill,
                              child: Container(color: tone),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: isExpanded && _hasDetails
                    ? Padding(
                        padding: const EdgeInsets.only(top: V2Spacing.space8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!_isExactZero && _hasReason)
                              Text(
                                pillar.effectiveReason!,
                                style: V2Typography.bodySm(
                                  color: context.v2.fgMuted,
                                ),
                              ),
                            for (final fact in pillar.facts) ...[
                              const SizedBox(height: V2Spacing.space8),
                              _PillarFact(fact: fact),
                            ],
                            if (_hasAction) ...[
                              const SizedBox(height: V2Spacing.space8),
                              TextButton(
                                onPressed: pillar.onAction,
                                child: Text(pillar.actionLabel!),
                              ),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillarFact extends StatelessWidget {
  final V4PillarFact fact;
  const _PillarFact({required this.fact});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(fact.label, style: V2Typography.caption(color: context.v2.fgMuted)),
      Text(fact.valueDisplay, style: V2Typography.bodySm(color: context.v2.fg)),
      if (fact.detail != null) ...[
        const SizedBox(height: 2),
        Text(
          fact.detail!,
          style: V2Typography.caption(color: context.v2.fgMuted),
        ),
      ],
    ],
  );
}
