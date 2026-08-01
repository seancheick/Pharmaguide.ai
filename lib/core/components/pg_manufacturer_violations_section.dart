import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_review_before_use_card.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One FDA / regulatory violation against the product's manufacturer.
class PGViolation {
  /// Severity drives the leading dot color + sort order.
  final PGReviewTone severity;

  /// Violation type slug from the pipeline, humanized
  /// ("GMP non-compliance", "Warning letter").
  final String type;

  /// Date string ("2023-04-15" or pre-formatted "April 2023").
  final String? date;

  /// Optional Dr. Pham–authored summary explaining why this matters.
  final String trustSummary;

  /// Optional source/reference identifier from the FDA/enforcement feed.
  final String? referenceId;

  /// Tap → opens production's violation detail sheet.
  final VoidCallback? onTap;

  const PGViolation({
    required this.severity,
    required this.type,
    required this.trustSummary,
    this.date,
    this.referenceId,
    this.onTap,
  });
}

/// Lists FDA violations from the manufacturer (typically 1-5 visible
/// with "+N more" overflow). Each row: severity dot + type + date +
/// Dr. Pham–authored trust summary.
class PGManufacturerViolationsSection extends StatelessWidget {
  final List<PGViolation> violations;
  final String title;

  /// Number of violations to show before collapsing the rest under
  /// "View N more". Production: 5.
  final int collapseThreshold;

  const PGManufacturerViolationsSection({
    super.key,
    required this.violations,
    this.title = 'Manufacturer history',
    this.collapseThreshold = 5,
  });

  @override
  Widget build(BuildContext context) {
    if (violations.isEmpty) return const SizedBox.shrink();
    final visible = violations.take(collapseThreshold).toList(growable: false);
    final overflow = violations.length - visible.length;

    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: V2Typography.titleSm(color: context.v2.fg)),
          const SizedBox(height: V2Spacing.space12),
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: V2Spacing.space12),
            _ViolationRow(violation: visible[i]),
          ],
          if (overflow > 0) ...[
            const SizedBox(height: V2Spacing.space12),
            Text(
              '+ $overflow more violation${overflow == 1 ? '' : 's'} on file',
              style: V2Typography.label(color: context.v2.accent),
            ),
          ],
        ],
      ),
    );
  }
}

class _ViolationRow extends StatelessWidget {
  final PGViolation violation;
  const _ViolationRow({required this.violation});

  @override
  Widget build(BuildContext context) {
    final tone = violation.severity.tint;
    final card = Container(
      padding: const EdgeInsets.all(V2Spacing.space12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: tone.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
              ),
              const SizedBox(width: V2Spacing.space8),
              Expanded(
                child: Text(
                  violation.type,
                  style: V2Typography.bodyMedium(color: context.v2.fg),
                ),
              ),
              if (violation.date != null) ...[
                const SizedBox(width: V2Spacing.space8),
                Text(
                  violation.date!,
                  style: V2Typography.caption(color: context.v2.fgMuted),
                ),
              ],
            ],
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            violation.trustSummary,
            style: V2Typography.bodySm(color: context.v2.fgMuted),
          ),
          if (violation.referenceId != null) ...[
            const SizedBox(height: V2Spacing.space4),
            Text(
              'Ref: ${violation.referenceId}',
              style: V2Typography.caption(color: context.v2.fgMuted),
            ),
          ],
        ],
      ),
    );

    if (violation.onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: violation.onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: card,
      ),
    );
  }
}
