import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 goal selection chip — used by onboarding goal picker and any
/// similar "pick from a curated list" surfaces.
///
/// Visual states:
/// - **Selected**: accent tint background, accent border, accent label (500)
/// - **Unselected**: surface background, hairline outline, fg label (400)
/// - **Disabled** (e.g. max selections reached): outline subdued, label muted
///
/// Pill radius. No checkmark icon — selection is communicated entirely
/// through color shift, which keeps the chip compact and editorial.
class PGGoalChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const PGGoalChip({
    super.key,
    required this.label,
    required this.selected,
    this.disabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? context.v2.accentTint : context.v2.surface;
    final border = selected
        ? context.v2.accent
        : (disabled ? context.v2.outline : context.v2.outline);
    final fg = disabled
        ? context.v2.fgSubtle
        : (selected ? context.v2.accent : context.v2.fg);

    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: label,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: V2Motion.fast,
          curve: V2Motion.smooth,
          padding: const EdgeInsets.symmetric(
            horizontal: V2Spacing.space16,
            vertical: V2Spacing.space12,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            border: Border.all(color: border, width: selected ? 1.5 : 1.0),
          ),
          child: Text(
            label,
            style: selected
                ? V2Typography.label(color: fg)
                : V2Typography.bodySm(color: fg),
          ),
        ),
      ),
    );
  }
}
