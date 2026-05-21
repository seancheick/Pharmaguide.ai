// PGTimingAdviceCard — Phase 11.7L.C.
//
// V2 stack timing advice surface. Same data, same rule-type vocabulary,
// same maxVisible cap:
//
//   * Cream `V2Colors.surface` card with a 4px accent-tint left
//     stripe — keeps the section visually "positive guidance"
//     (efficacy advice) rather than a warning.
//   * Mono-caps "TIMING · {N}" eyebrow + Newsreader-adjacent title
//     "Timing optimization" in v2 typography.
//   * Per-rule rows use accent / monitor / caution tints from
//     `V2Colors` instead of the retired v1 severity colors.
//   * "+N more timing tips" footer in mono-caps for parity with the
//     other v2 sections.
//
// Behavior preserves the production data contract — no data shape change.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

class PGTimingAdviceCard extends StatelessWidget {
  const PGTimingAdviceCard({
    super.key,
    required this.optimizations,
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.maxVisible = 3,
  });

  /// Timing optimizations from `StackSafetyReport.timingOptimizations`.
  /// Pre-sorted by priority — separations first, then take-with-food /
  /// empty-stomach, then time-of-day.
  final List<TimingOptimization> optimizations;

  /// Tap → full timing detail screen (caller wires the navigation).
  final VoidCallback? onTap;

  /// Outer margin — match the section above (typically the v2 safety
  /// banner) so vertical rhythm holds.
  final EdgeInsetsGeometry margin;

  /// Maximum number of timing items rendered inline before "+N more".
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (optimizations.isEmpty) return const SizedBox.shrink();

    final separations = optimizations
        .where((o) => o.isSeparation)
        .toList(growable: false);
    final others = optimizations
        .where((o) => !o.isSeparation)
        .toList(growable: false);
    final visible = [...separations, ...others].take(maxVisible).toList();

    final card = Container(
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: ColoredBox(
              color: V2Colors.accent,
              child: SizedBox(width: 4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(V2Spacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: V2Colors.accent,
                    ),
                    const SizedBox(width: V2Spacing.space8),
                    PGEyebrow(
                      'Timing  ·  ${optimizations.length}',
                      color: V2Colors.accent,
                    ),
                  ],
                ),
                const SizedBox(height: V2Spacing.space8),
                Text(
                  // Sean 2026-05-16: pluralize when there are
                  // multiple tips. Singular reads slightly off
                  // when there are 3+ rules below it.
                  optimizations.length > 1
                      ? 'Timing optimizations'
                      : 'Timing optimization',
                  style: V2Typography.titleSm(color: V2Colors.fg),
                ),
                const SizedBox(height: V2Spacing.space12),
                for (var i = 0; i < visible.length; i++) ...[
                  _TimingRow(opt: visible[i]),
                  if (i < visible.length - 1)
                    const SizedBox(height: V2Spacing.space12),
                ],
                if (optimizations.length > maxVisible) ...[
                  const SizedBox(height: V2Spacing.space12),
                  Text(
                    '+${optimizations.length - maxVisible} more timing tips',
                    style: V2Typography.label(color: V2Colors.accent),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: margin,
      child: onTap == null
          ? card
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
                child: card,
              ),
            ),
    );
  }
}

class _TimingRow extends StatelessWidget {
  const _TimingRow({required this.opt});

  final TimingOptimization opt;

  @override
  Widget build(BuildContext context) {
    final icon = _iconFor(opt.ruleType);
    final color = _colorFor(opt.ruleType);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: V2Spacing.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _summaryFor(opt),
                style: V2Typography.bodySm(color: V2Colors.fg),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (opt.separationHours != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${opt.separationHours}h apart',
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static IconData _iconFor(TimingRuleType type) {
    switch (type) {
      case TimingRuleType.separate:
        return Icons.swap_horiz_rounded;
      case TimingRuleType.takeTogether:
        return Icons.link_rounded;
      case TimingRuleType.takeWithFood:
        return Icons.restaurant_rounded;
      case TimingRuleType.takeOnEmptyStomach:
        return Icons.no_food_rounded;
      case TimingRuleType.timeOfDay:
        return Icons.wb_sunny_rounded;
    }
  }

  /// V2 tint palette for each rule type. Separations carry the most
  /// weight (timing matters most) — render as caution. The rest are
  /// neutral / accent: positive optimization guidance, not warning.
  static Color _colorFor(TimingRuleType type) {
    switch (type) {
      case TimingRuleType.separate:
        return V2Colors.caution;
      case TimingRuleType.takeTogether:
        return V2Colors.accent;
      case TimingRuleType.takeWithFood:
      case TimingRuleType.takeOnEmptyStomach:
        return V2Colors.monitor;
      case TimingRuleType.timeOfDay:
        return V2Colors.fgMuted;
    }
  }

  static String _summaryFor(TimingOptimization opt) {
    final p1 = opt.product1Name ?? opt.ingredient1;
    final p2 = opt.product2Name ?? opt.ingredient2;
    switch (opt.ruleType) {
      case TimingRuleType.separate:
        return 'Take $p1 and $p2 separately';
      case TimingRuleType.takeTogether:
        return 'Take $p1 with $p2 for better absorption';
      case TimingRuleType.takeWithFood:
        return 'Take $p1 with a meal';
      case TimingRuleType.takeOnEmptyStomach:
        return 'Take $p1 on an empty stomach';
      case TimingRuleType.timeOfDay:
        return opt.advice.length <= 60
            ? opt.advice
            : 'Best time for $p1: check details';
    }
  }
}
