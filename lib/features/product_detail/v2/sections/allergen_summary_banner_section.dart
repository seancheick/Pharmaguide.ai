// Allergen summary fallback section.
//
// Renders when:
//   • product is not blocked AND
//   • `_product.allergenSummary` is non-empty free text AND
//   • the blob has NO structured allergens (which would have already
//     rendered as personalized rows in ReviewBeforeUseCard).
//
// The connected screen calls `shouldShowAllergenSummaryBanner(...)`
// from `v2/gating.dart` with the pre-computed `matchAllergens(...).isEmpty`
// flag, then renders this section adapter when true.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Build the allergen summary fallback section (free-text allergen info).
///
/// This is UNMATCHED free text — there is no structured profile match — so
/// it is framed conservatively ("Check the label for your allergens") rather
/// than presented as an authoritative match. Returns `SizedBox.shrink()`
/// when the summary is null/empty. The gate is enforced upstream by
/// `shouldShowAllergenSummaryBanner`.
Widget buildAllergenSummaryBannerSection({required String? allergenSummary}) {
  if (allergenSummary == null || allergenSummary.trim().isEmpty) {
    return const SizedBox.shrink();
  }
  return _allergenBanner(
    accent: V2Colors.caution,
    icon: Icons.warning_amber_rounded,
    title: 'Check the label for your allergens',
    text: allergenSummary.trim(),
  );
}

/// Build the "allergen data unavailable" hedge — shown to users with
/// declared allergens when the product carries no allergen data at all.
/// Info-toned (not an alarm): "unknown != safe" means the absence of data
/// must read as "check the label", never as a silent clean bill. The gate
/// is enforced upstream by `shouldShowAllergenDataUnavailableHedge`.
Widget buildAllergenDataUnavailableHedge() {
  return _allergenBanner(
    accent: V2Colors.monitor,
    icon: Icons.info_outline_rounded,
    text: "Allergen data isn't available for this product — check the "
        'label for your allergens.',
  );
}

/// Shared left-accent info/caution banner used by the allergen fallback
/// surfaces. Keeps the two builders visually identical apart from tone.
Widget _allergenBanner({
  required Color accent,
  required IconData icon,
  required String text,
  String? title,
}) {
  return Container(
    decoration: BoxDecoration(
      color: V2Colors.surface,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      border: Border.all(color: V2Colors.outline),
      boxShadow: V2Shadows.sm,
    ),
    clipBehavior: Clip.antiAlias,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 3, color: accent),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(V2Spacing.space12),
              color: accent.withValues(alpha: 0.06),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: V2Spacing.space8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title != null) ...[
                          Text(
                            title,
                            style: V2Typography.bodySm(
                              color: V2Colors.fg,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          text,
                          style: V2Typography.bodySm(color: V2Colors.fg),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
