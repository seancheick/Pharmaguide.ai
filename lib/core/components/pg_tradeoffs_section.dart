import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One tradeoff bullet — a "Pro" (positive) or a "Consideration" (caveat).
class PGTradeoff {
  final String headline;

  /// Optional 1-line caption beneath the headline ("Strong evidence" /
  /// "Limited data" — production parses these from score_bonuses /
  /// score_penalties evidence fields).
  final String? caption;

  /// Number of points this tradeoff contributed (positive or negative).
  /// Production shows e.g. "+2 / -3" alongside the headline. Optional.
  final int? points;

  const PGTradeoff({required this.headline, this.caption, this.points});
}

/// Two-column "What's good / What to consider" layout — same visual
/// intent as production. Each column has its own eyebrow + a bulleted
/// list. Columns hide when empty so a product with only pros shows
/// only the green column.
class PGTradeoffsSection extends StatelessWidget {
  final List<PGTradeoff> pros;
  final List<PGTradeoff> considerations;
  final Widget? considerationLeading;

  /// Header title. Production uses "Tradeoffs". Defaulted here.
  final String title;

  const PGTradeoffsSection({
    super.key,
    this.pros = const [],
    this.considerations = const [],
    this.considerationLeading,
    this.title = 'Tradeoffs',
  });

  @override
  Widget build(BuildContext context) {
    final hasConsiderations =
        considerations.isNotEmpty || considerationLeading != null;
    if (pros.isEmpty && !hasConsiderations) return const SizedBox.shrink();
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
          const SizedBox(height: V2Spacing.space16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pros.isNotEmpty)
                Expanded(
                  child: _TradeoffColumn(
                    eyebrow: 'What\'s good',
                    eyebrowColor: V2Colors.safe,
                    items: pros,
                    dotColor: V2Colors.safe,
                    overflowSingularNoun: 'bonus',
                  ),
                ),
              if (pros.isNotEmpty && hasConsiderations)
                const SizedBox(width: V2Spacing.space16),
              if (hasConsiderations)
                Expanded(
                  child: _TradeoffColumn(
                    eyebrow: 'What to consider',
                    eyebrowColor: V2Colors.caution,
                    items: considerations,
                    dotColor: V2Colors.caution,
                    overflowSingularNoun: 'concern',
                    leading: considerationLeading,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TradeoffColumn extends StatelessWidget {
  final String eyebrow;
  final Color eyebrowColor;
  final List<PGTradeoff> items;
  final Color dotColor;
  final String overflowSingularNoun;
  final Widget? leading;

  const _TradeoffColumn({
    required this.eyebrow,
    required this.eyebrowColor,
    required this.items,
    required this.dotColor,
    required this.overflowSingularNoun,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return _ExpandableTradeoffColumn(
      eyebrow: eyebrow,
      eyebrowColor: eyebrowColor,
      items: items,
      dotColor: dotColor,
      overflowSingularNoun: overflowSingularNoun,
      leading: leading,
    );
  }
}

class _ExpandableTradeoffColumn extends StatefulWidget {
  final String eyebrow;
  final Color eyebrowColor;
  final List<PGTradeoff> items;
  final Color dotColor;
  final String overflowSingularNoun;
  final Widget? leading;

  const _ExpandableTradeoffColumn({
    required this.eyebrow,
    required this.eyebrowColor,
    required this.items,
    required this.dotColor,
    required this.overflowSingularNoun,
    this.leading,
  });

  @override
  State<_ExpandableTradeoffColumn> createState() =>
      _ExpandableTradeoffColumnState();
}

class _ExpandableTradeoffColumnState extends State<_ExpandableTradeoffColumn> {
  static const _visibleCap = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final overflow = widget.items.length - _visibleCap;
    final visible = _expanded
        ? widget.items
        : widget.items.take(_visibleCap).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PGEyebrow(widget.eyebrow, color: widget.eyebrowColor),
        const SizedBox(height: V2Spacing.space12),
        if (widget.leading != null) ...[
          widget.leading!,
          if (visible.isNotEmpty) const SizedBox(height: V2Spacing.space8),
        ],
        for (final item in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: V2Spacing.space8),
            child: _TradeoffRow(item: item, dotColor: widget.dotColor),
          ),
        if (overflow > 0) ...[
          const SizedBox(height: V2Spacing.space4),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: V2Spacing.space4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded
                        ? 'Show less'
                        : overflow == 1
                        ? 'Show 1 more ${widget.overflowSingularNoun}'
                        : 'Show $overflow more '
                              '${_pluralize(widget.overflowSingularNoun)}',
                    style: V2Typography.label(color: V2Colors.fgMuted),
                  ),
                  const SizedBox(width: V2Spacing.space4),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: V2Colors.fgMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

String _pluralize(String singular) {
  final lower = singular.toLowerCase();
  if (lower.endsWith('s') ||
      lower.endsWith('x') ||
      lower.endsWith('z') ||
      lower.endsWith('sh') ||
      lower.endsWith('ch')) {
    return '${singular}es';
  }
  return '${singular}s';
}

class _TradeoffRow extends StatelessWidget {
  final PGTradeoff item;
  final Color dotColor;

  const _TradeoffRow({required this.item, required this.dotColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, right: V2Spacing.space8),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.headline,
                style: V2Typography.bodySm(color: V2Colors.fg),
              ),
              if (item.caption != null) ...[
                const SizedBox(height: 2),
                Text(
                  item.caption!,
                  style: V2Typography.caption(color: V2Colors.fgMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
