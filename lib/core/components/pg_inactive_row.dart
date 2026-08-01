import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';

/// Canonical inactive-ingredient row for the Product Detail ingredients
/// card.
///
/// - 8pt colored dot driven by `InactiveTone` (green / yellow / orange /
///   red). Color comes from the `InactiveToneColor` extension.
/// - Name (Geist Sans 500, ellipsis on overflow)
/// - Optional role helper line (12pt onSurfaceVariant) below the name
/// - Bottom hairline (0.4pt outlineVariant) except on the last row
/// - Tap anywhere → `onTap` (Product Detail wires it to
///   `showFunctionalRolesSheet`)
class PGInactiveRow extends StatelessWidget {
  final PGInactiveIngredient ingredient;

  /// When true, skip the bottom divider. Composing [PGIngredientsCard]
  /// passes true for the final row so the list ends cleanly inside the
  /// card padding.
  final bool isLast;

  /// Opens the functional-roles bottom sheet via
  /// `showFunctionalRolesSheet`. Null hides the inkwell ripple +
  /// disables the tap.
  final VoidCallback? onTap;

  const PGInactiveRow({
    super.key,
    required this.ingredient,
    this.isLast = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    bottom: BorderSide(color: context.v2.outline, width: 0.4),
                  ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: V2Spacing.space8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: ingredient.tone.color(context.v2),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ingredient.name,
                        style: V2Typography.bodyMedium(color: context.v2.fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (ingredient.roleHelper != null &&
                          ingredient.roleHelper!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          ingredient.roleHelper!,
                          style: V2Typography.caption(color: context.v2.fgMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
