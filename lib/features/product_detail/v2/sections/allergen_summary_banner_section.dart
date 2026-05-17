// Phase 11.7f — AllergenSummaryBanner section adapter (S18, LEGACY).
//
// Adapts the legacy `AllergenSummaryBanner` (lib/features/
// product_detail/widgets/pipeline_sections/
// allergen_summary_banner.dart) onto the v2 product detail surface.
//
// **Legacy fallback only.** Renders when:
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

/// Build the AllergenSummaryBanner legacy fallback section.
///
/// Returns `SizedBox.shrink()` when the summary is null/empty. The gate
/// is enforced upstream by `shouldShowAllergenSummaryBanner` — this
/// helper only renders the visual presentation.
Widget buildAllergenSummaryBannerSection({
  required String? allergenSummary,
}) {
  if (allergenSummary == null || allergenSummary.trim().isEmpty) {
    return const SizedBox.shrink();
  }

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
          Container(width: 3, color: V2Colors.caution),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(V2Spacing.space12),
              color: V2Colors.caution.withValues(alpha: 0.06),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: V2Colors.caution,
                  ),
                  const SizedBox(width: V2Spacing.space8),
                  Expanded(
                    child: Text(
                      allergenSummary.trim(),
                      style: V2Typography.bodySm(color: V2Colors.fg),
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
