// Phase 11.7c.4 — LabelConfidence section adapter.
//
// Composes the v2 PGLabelConfidenceCard using analysis signals plus the
// independent pipeline label-ledger audit:
//
//   mappedCoverage         (_product.mappedCoverage)
//   hasProprietaryBlends   (detailBlob.proprietary_blend_detail.has_proprietary_blends)
//   isNotScored            (productIsNotScored gate)
//   productStatus          (detailBlob.product_status)
//   unmappedActives        (detailBlob.unmapped_actives)
//   labelLedgerAudit       (detailBlob.label_ledger_audit)
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
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
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
///
/// **Phase 11.7h.2 — Sean 2026-05-16 compact note-tier:**
/// When the only signal is product_status (note tier), render a
/// compact single-row variant instead of the full PGLabelConfidenceCard
/// header + row layout. Removes the "Product note" + "Product
/// discontinued" redundancy. The status label becomes the row title
/// directly, chevron + tap-to-explanation preserved.
Widget buildLabelConfidenceSection({
  required BuildContext context,
  required double mappedCoverage,
  required bool hasProprietaryBlends,
  required bool isNotScored,
  Map<String, dynamic>? productStatus,
  Map<String, dynamic>? unmappedActives,
  Map<String, dynamic>? labelLedgerAudit,
  bool labelLedgerAuditPresent = false,
}) {
  final tier = computeLabelConfidenceTier(
    mappedCoverage: mappedCoverage,
    hasProprietaryBlends: hasProprietaryBlends,
    isNotScored: isNotScored,
    unmappedActives: unmappedActives,
  );

  // Compact note-tier path — only product_status fires, nothing else. A
  // ledger audit EXCEPTION uses the full card so its result cannot be
  // conflated with a product-status note; a clean 100% audit is silent.
  final hasLabelLedgerException =
      labelCompletenessPresentation(
        labelLedgerAudit,
        auditPresent: labelLedgerAuditPresent,
      )?.isException ??
      false;
  if (tier == LabelConfidenceTier.note && !hasLabelLedgerException) {
    final label = productStatusLabel(productStatus);
    if (label == null) return const SizedBox.shrink();
    return _CompactNoteRow(
      label: label,
      onTap: () =>
          _showProductStatusSheet(context, productStatusType(productStatus)),
    );
  }

  // Standard partial / limited tier path — full PGLabelConfidenceCard.
  final items = buildLabelConfidenceItems(
    mappedCoverage: mappedCoverage,
    hasProprietaryBlends: hasProprietaryBlends,
    isNotScored: isNotScored,
    productStatus: productStatus,
    unmappedActives: unmappedActives,
    labelLedgerAudit: labelLedgerAudit,
    labelLedgerAuditPresent: labelLedgerAuditPresent,
    onTapProductStatus: () =>
        _showProductStatusSheet(context, productStatusType(productStatus)),
  );

  if (items.isEmpty) return const SizedBox.shrink();

  final hasAnalysisSignal =
      isNotScored ||
      mappedCoverage < 0.5 ||
      hasProprietaryBlends ||
      unmappedTotal(unmappedActives) > 0;
  final header = !hasLabelLedgerException
      ? composeHeader(tier)
      : hasAnalysisSignal
      ? 'Label & analysis data'
      : 'Label data';

  return Semantics(
    container: true,
    label: coverageSemanticsLabel(
      tier: tier,
      mappedCoverage: mappedCoverage,
      hasProprietaryBlends: hasProprietaryBlends,
      isNotScored: isNotScored,
      unmappedActives: unmappedActives,
      labelLedgerAudit: labelLedgerAudit,
      labelLedgerAuditPresent: labelLedgerAuditPresent,
    ),
    child: PGLabelConfidenceCard(
      header: header,
      items: items,
      isCaution:
          isCautionTier(tier) ||
          labelCompletenessPresentation(
                labelLedgerAudit,
                auditPresent: labelLedgerAuditPresent,
              )?.title ==
              'Label completeness unavailable',
    ),
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
  Map<String, dynamic>? labelLedgerAudit,
  bool labelLedgerAuditPresent = false,
}) {
  if (isNotScored) return true;
  if (mappedCoverage < 0.5) return true;
  if (hasProprietaryBlends) return true;
  if (unmappedTotal(unmappedActives) > 0) return true;
  if (productStatusLabel(productStatus) != null) return true;
  // A ledger audit is only a signal when it reports an EXCEPTION; a clean
  // 100%-complete label stays invisible.
  final completeness = labelCompletenessPresentation(
    labelLedgerAudit,
    auditPresent: labelLedgerAuditPresent,
  );
  if (completeness != null && completeness.isException) return true;
  return false;
}

/// Compact one-row variant for note-tier status-only state. Replaces
/// the redundant "Product note" header + "Product discontinued · ..."
/// row pattern. Single tappable row with info icon, status label,
/// and chevron — leads to the same explanation sheet.
class _CompactNoteRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CompactNoteRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label. Opens product status details.',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: V2Spacing.space16,
              vertical: V2Spacing.space12,
            ),
            decoration: BoxDecoration(
              color: context.v2.surface,
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: context.v2.outline),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_busy_outlined,
                  size: 18,
                  color: context.v2.fgMuted,
                ),
                const SizedBox(width: V2Spacing.space12),
                Expanded(
                  child: Text(
                    label,
                    style: V2Typography.bodyMedium(color: context.v2.fg),
                  ),
                ),
                const SizedBox(width: V2Spacing.space8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: context.v2.fgMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
              style: V2Typography.titleSm(color: context.v2.fg),
            ),
            const SizedBox(height: V2Spacing.space12),
            Text(
              productStatusExplanationBody(type),
              style: V2Typography.bodySm(color: context.v2.fgMuted),
            ),
          ],
        ),
      );
    },
  );
}
