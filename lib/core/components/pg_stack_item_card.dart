import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_product_thumbnail.dart';
import 'package:pharmaguide/core/components/pg_score_chip.dart';
import 'package:pharmaguide/core/components/pg_severity_badge.dart';
import 'package:pharmaguide/core/components/pg_type_badge.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One row in the user's stack — thumbnail + name + brand + dose / freq +
/// optional severity badge + optional score chip.
///
/// Composes the v2 primitives into a uniform row layout:
/// - 56pt thumbnail (PGProductThumbnail handles image / bottle placeholder)
/// - Sans name (max 2 lines, no `…` on short names — falls back gracefully)
/// - Mono caps brand eyebrow
/// - Body-small dose / frequency line
/// - Optional PGSeverityBadge on the bottom-left (only when there's
///   something to flag — most rows render quiet)
/// - PGScoreChip on the right when [score] is set (supplements have
///   scores; medications usually don't)
///
/// **Compact-first** design — height stays manageable across long lists.
/// When [expanded] is true, the row reveals extra detail (effects,
/// indications) inline. Toggle expansion at the parent via [onTap] /
/// state.
class PGStackItemCard extends StatelessWidget {
  final String name;
  final String? brand;
  final String? doseLine;
  final String? imageUrl;
  final PGItemType type;
  final double? score;
  final PGSeverity? flagSeverity;
  final String? flagLabel;
  final bool expanded;

  /// Optional secondary content shown only when [expanded] is true.
  /// e.g. notes, "Why it's in your stack", interaction summary.
  final Widget? expandedDetails;

  final VoidCallback? onTap;

  /// Optional long-press handler — useful for quick actions
  /// (mark inactive, edit dose).
  final VoidCallback? onLongPress;

  const PGStackItemCard({
    super.key,
    required this.name,
    required this.type,
    this.brand,
    this.doseLine,
    this.imageUrl,
    this.score,
    this.flagSeverity,
    this.flagLabel,
    this.expanded = false,
    this.expandedDetails,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Colors.surface,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: AnimatedSize(
          duration: V2Motion.base,
          curve: V2Motion.smooth,
          alignment: Alignment.topCenter,
          child: Container(
            padding: const EdgeInsets.all(V2Spacing.space16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: V2Colors.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PGProductThumbnail(
                      imageUrl: imageUrl,
                      type: type,
                      size: 56,
                    ),
                    const SizedBox(width: V2Spacing.space16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (brand != null) ...[
                            PGEyebrow(brand!, color: V2Colors.fgMuted),
                            const SizedBox(height: V2Spacing.space4),
                          ],
                          Text(
                            name,
                            style: V2Typography.bodyMedium(
                              color: V2Colors.fg,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (doseLine != null) ...[
                            const SizedBox(height: V2Spacing.space4),
                            Text(
                              doseLine!,
                              style: V2Typography.bodySm(
                                color: V2Colors.fgMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (score != null) ...[
                      const SizedBox(width: V2Spacing.space12),
                      PGScoreChip(score: score!, showCaption: false),
                    ],
                  ],
                ),
                if (flagSeverity != null) ...[
                  const SizedBox(height: V2Spacing.space12),
                  PGSeverityBadge(
                    severity: flagSeverity!,
                    label: flagLabel,
                  ),
                ],
                if (expanded && expandedDetails != null) ...[
                  const SizedBox(height: V2Spacing.space16),
                  const Divider(color: V2Colors.outline, height: 1),
                  const SizedBox(height: V2Spacing.space16),
                  expandedDetails!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
