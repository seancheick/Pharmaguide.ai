// Phase 11.7c.4 — LabelConfidence section adapter.
//
// V2 mirror of production's `LabelConfidenceCard` (line 414 in
// product_detail_screen.dart). Composes the v2 PGLabelConfidenceCard
// using the same 5 signals production uses:
//
//   mappedCoverage         (_product.mappedCoverage)
//   hasProprietaryBlends   (detailBlob.proprietary_blend_detail.has_proprietary_blends)
//   isNotScored            (productIsNotScored gate)
//   productStatus          (detailBlob.product_status)
//   unmappedActives        (detailBlob.unmapped_actives)
//
// All tier + row composition lives in `label_confidence_helpers.dart`
// to keep this file pure widget composition.
//
// Sean's rules (2026-05-15) — preserved verbatim:
//   • Preserve `hasAnySignal` gate semantics. Caller passes the boolean
//     via `shouldShowLabelConfidence`.
//   • Preserve tier rules verbatim (note / partial / limited).
//   • Preserve row order — isNotScored → coverage → blends → unmapped →
//     productStatus.
//   • Never red. Calm caveat block, not a warning.
//   • Tap on the product-status row opens the same explanation sheet
//     production renders via PGModal.

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_label_confidence_card.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/widgets/pg_modal.dart';
import 'package:pharmaguide/features/product_detail/v2/sections/label_confidence_helpers.dart';

/// Build the LabelConfidence section widget. The connected screen
/// computes `hasAnySignal` (via `LabelConfidenceCard.hasAnySignal` or
/// directly from the 5 inputs) and gates this call so a no-signal
/// product hides the section entirely.
///
/// Returns `SizedBox.shrink()` defensively when the resulting item
/// list is empty (should not happen when `hasAnySignal` is true).
Widget buildLabelConfidenceSection({
  required BuildContext context,
  required double mappedCoverage,
  required bool hasProprietaryBlends,
  required bool isNotScored,
  Map<String, dynamic>? productStatus,
  Map<String, dynamic>? unmappedActives,
}) {
  final tier = computeLabelConfidenceTier(
    mappedCoverage: mappedCoverage,
    hasProprietaryBlends: hasProprietaryBlends,
    isNotScored: isNotScored,
    unmappedActives: unmappedActives,
  );
  final items = buildLabelConfidenceItems(
    mappedCoverage: mappedCoverage,
    hasProprietaryBlends: hasProprietaryBlends,
    isNotScored: isNotScored,
    productStatus: productStatus,
    unmappedActives: unmappedActives,
    onTapProductStatus: () => _showProductStatusSheet(
      context,
      productStatusType(productStatus),
    ),
  );

  if (items.isEmpty) return const SizedBox.shrink();

  return PGLabelConfidenceCard(
    header: composeHeader(tier),
    items: items,
    isCaution: isCautionTier(tier),
  );
}

/// True when at least one of the 5 signals fires. Mirrors production's
/// `LabelConfidenceCard.hasAnySignal` so the connected screen can gate
/// the sliver without depending on the production widget transitively.
bool labelConfidenceHasAnySignal({
  required double mappedCoverage,
  required bool hasProprietaryBlends,
  required bool isNotScored,
  Map<String, dynamic>? productStatus,
  Map<String, dynamic>? unmappedActives,
}) {
  if (isNotScored) return true;
  if (mappedCoverage < 0.5) return true;
  if (hasProprietaryBlends) return true;
  if (unmappedTotal(unmappedActives) > 0) return true;
  if (productStatusLabel(productStatus) != null) return true;
  return false;
}

/// Show the product-status explanation bottom sheet. Mirrors
/// production's `_ProductStatusExplanationSheet` (line 402) — same
/// modal copy, v2 typography on the cream surface.
void _showProductStatusSheet(BuildContext context, String? type) {
  PGModal.bottomSheet<void>(
    context: context,
    showDragHandle: false,
    builder: (_) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          V2Spacing.space16,
          V2Spacing.space16,
          V2Spacing.space16,
          V2Spacing.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About this product status',
              style: V2Typography.titleSm(color: V2Colors.fg),
            ),
            const SizedBox(height: V2Spacing.space12),
            Text(
              productStatusExplanationBody(type),
              style: V2Typography.bodySm(color: V2Colors.fgMuted),
            ),
          ],
        ),
      );
    },
  );
}
