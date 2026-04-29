// TimingAdviceCard — renders timing optimization advice for the user's stack.
//
// Displayed below the safety banner when TimingEvaluationService produces
// results. Shows a compact summary of timing rules that apply to the
// current stack — separation rules (most actionable) first, then
// take-with-food/empty-stomach guidance, then time-of-day suggestions.
//
// Design principle: this is POSITIVE guidance, not a warning. The tone
// is informational/helpful (blue/teal), not alarming (red/amber).
// Timing advice improves efficacy, not safety — the user's stack is
// safe regardless, but they can get more out of their supplements by
// following timing advice.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/models/timing_optimization.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

class TimingAdviceCard extends StatelessWidget {
  const TimingAdviceCard({
    super.key,
    required this.optimizations,
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.maxVisible = 3,
  });

  /// Timing optimizations from [StackSafetyReport.timingOptimizations].
  /// Expected to be pre-sorted by priority (medication separations first).
  final List<TimingOptimization> optimizations;

  /// Tap handler to navigate to the full timing detail screen.
  final VoidCallback? onTap;

  /// Outer margin matching [StackSafetyBanner] spacing.
  final EdgeInsetsGeometry margin;

  /// Maximum number of timing items to show inline before "N more".
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (optimizations.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final separations = optimizations
        .where((o) => o.isSeparation)
        .toList(growable: false);
    final others = optimizations
        .where((o) => !o.isSeparation)
        .toList(growable: false);

    return Padding(
      padding: margin,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          side: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
          ),
        ),
        color: theme.colorScheme.primary.withValues(alpha: 0.04),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppTheme.space8),
                    Text(
                      'Timing Optimization',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (optimizations.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMedium,
                          ),
                        ),
                        child: Text(
                          '${optimizations.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppTheme.space12),

                // Show top items inline
                ..._buildVisibleItems(context, separations, others),

                // "View all" link
                if (optimizations.length > maxVisible) ...[
                  const SizedBox(height: AppTheme.space8),
                  Text(
                    '+${optimizations.length - maxVisible} more timing tips',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildVisibleItems(
    BuildContext context,
    List<TimingOptimization> separations,
    List<TimingOptimization> others,
  ) {
    final items = <Widget>[];
    final allSorted = [...separations, ...others];
    final visible = allSorted.take(maxVisible);

    for (final opt in visible) {
      items.add(_TimingItemRow(optimization: opt));
      if (opt != visible.last) {
        items.add(const SizedBox(height: AppTheme.space8));
      }
    }
    return items;
  }
}

class _TimingItemRow extends StatelessWidget {
  const _TimingItemRow({required this.optimization});

  final TimingOptimization optimization;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _iconFor(optimization.ruleType);
    final color = _colorFor(optimization.ruleType, theme);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppTheme.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _summaryFor(optimization),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (optimization.separationHours != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${optimization.separationHours}h apart',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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

  static Color _colorFor(TimingRuleType type, ThemeData theme) {
    switch (type) {
      case TimingRuleType.separate:
        return theme.colorScheme.error.withValues(alpha: 0.7);
      case TimingRuleType.takeTogether:
        return theme.colorScheme.primary;
      case TimingRuleType.takeWithFood:
      case TimingRuleType.takeOnEmptyStomach:
        return theme.colorScheme.tertiary;
      case TimingRuleType.timeOfDay:
        return theme.colorScheme.secondary;
    }
  }

  static String _summaryFor(TimingOptimization opt) {
    // Use product names when available for context.
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
