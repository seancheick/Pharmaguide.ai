import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_ingredient_data.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/product_detail/widgets/inactive_color.dart';

/// v2 mirror of `_InactiveRow` in
/// `lib/features/product_detail/widgets/ingredients_card.dart:219-330`.
///
/// **Same structure, semantics preserved verbatim:**
/// - 8pt colored dot driven by `InactiveTone` (green / yellow / orange /
///   red). Color comes from production `InactiveToneColor` extension on
///   `AppTheme.severity*` — no v2 remap.
/// - Name (Geist Sans 500, ellipsis on overflow)
/// - Optional role helper line (12pt onSurfaceVariant) below the name
/// - Bottom hairline (0.4pt outlineVariant) except on the last row
/// - Tap anywhere → `onTap` (production opens
///   `_showFunctionalRolesSheet` bottom sheet)
///
/// **What changes in v2:** typography swaps from bodyMedium w600 / bodySmall
/// 12sp to V2Typography.bodyMedium (Geist Sans 500) / V2Typography.caption.
/// Dot size, padding, hairline thickness preserved exactly.
class PGInactiveRow extends StatelessWidget {
  final PGInactiveIngredient ingredient;

  /// When true, skip the bottom divider. Composing [PGIngredientsCard]
  /// passes true for the final row so the list ends cleanly inside the
  /// card padding.
  final bool isLast;

  /// Production: opens `_FunctionalRolesSheet`. v2 prototype defers to
  /// caller — gallery passes a no-op or snackbar; production wiring
  /// passes the real sheet handler.
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
                : const Border(
                    bottom: BorderSide(color: V2Colors.outline, width: 0.4),
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
                    color: ingredient.tone.color,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ingredient.name,
                        style: V2Typography.bodyMedium(color: V2Colors.fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (ingredient.roleHelper != null &&
                          ingredient.roleHelper!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          ingredient.roleHelper!,
                          style: V2Typography.caption(color: V2Colors.fgMuted),
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
