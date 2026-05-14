import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_ingredient_chip.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_severity_badge.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One ingredient row data — used both for active and inactive lists.
class PGIngredient {
  final String name;
  final String? dose;
  final PGSeverity? severity;

  const PGIngredient({required this.name, this.dose, this.severity});
}

/// Compact, ranked ingredient stack.
///
/// Replaces the "endless vertical tile list" anti-pattern flagged in the
/// audit. Behavior:
/// - Renders the first [collapsedLimit] ingredients (default 5)
/// - If `ingredients.length > collapsedLimit`, shows "View all (N)" pill
///   that expands inline
/// - Expansion is instant (no scroll-from-bottom animation, per the
///   "motion never delays usability" rule)
/// - Severity-tinted chips only when severity is set; everything else
///   renders quietly
class PGIngredientStack extends StatefulWidget {
  final String eyebrow;
  final List<PGIngredient> ingredients;
  final int collapsedLimit;

  /// Optional explain handler — invoked when a chip is tapped with the
  /// ingredient name.
  final void Function(String name)? onExplain;

  const PGIngredientStack({
    super.key,
    required this.eyebrow,
    required this.ingredients,
    this.collapsedLimit = 5,
    this.onExplain,
  });

  @override
  State<PGIngredientStack> createState() => _PGIngredientStackState();
}

class _PGIngredientStackState extends State<PGIngredientStack> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final list = widget.ingredients;
    final shouldCollapse =
        !_expanded && list.length > widget.collapsedLimit;
    final visible = shouldCollapse
        ? list.take(widget.collapsedLimit).toList(growable: false)
        : list;
    final hiddenCount = list.length - widget.collapsedLimit;

    if (list.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PGEyebrow(widget.eyebrow),
          const SizedBox(height: V2Spacing.space12),
          Text(
            'No data available for this product yet.',
            style: V2Typography.body(color: V2Colors.fgMuted),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PGEyebrow(widget.eyebrow),
            const Spacer(),
            Text(
              '${list.length}',
              style: V2Typography.monoData(color: V2Colors.fgMuted),
            ),
          ],
        ),
        const SizedBox(height: V2Spacing.space12),
        AnimatedSize(
          duration: V2Motion.base,
          curve: V2Motion.smooth,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              for (final i in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: V2Spacing.space8),
                  child: PGIngredientChip(
                    name: i.name,
                    dose: i.dose,
                    severity: i.severity,
                    onTap: widget.onExplain == null
                        ? null
                        : () => widget.onExplain!(i.name),
                  ),
                ),
            ],
          ),
        ),
        if (shouldCollapse) ...[
          const SizedBox(height: V2Spacing.space4),
          PGPillButton(
            label: 'View all ($hiddenCount more)',
            variant: PGPillVariant.ghost,
            onPressed: () => setState(() => _expanded = true),
          ),
        ] else if (_expanded && list.length > widget.collapsedLimit) ...[
          const SizedBox(height: V2Spacing.space4),
          PGPillButton(
            label: 'Show fewer',
            variant: PGPillVariant.ghost,
            onPressed: () => setState(() => _expanded = false),
          ),
        ],
      ],
    );
  }
}
