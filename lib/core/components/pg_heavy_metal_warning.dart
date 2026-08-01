import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 heavy-metal warning card.
///
/// Conditional callout — only renders when the pipeline flags
/// `heavy_metal_risk == true`. Calm-clinical tone: amber warning, not
/// alarm red. Lists which metals (typically 1-2) with optional source
/// link.
class PGHeavyMetalWarning extends StatelessWidget {
  /// Specific metals detected ("Lead", "Cadmium", "Arsenic", "Mercury").
  /// Renders as a comma-separated list inline.
  final List<String> metals;

  /// 1-line context about the risk level.
  final String? note;

  /// Tap → opens production's source explanation modal.
  final VoidCallback? onTap;

  const PGHeavyMetalWarning({
    super.key,
    required this.metals,
    this.note,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (metals.isEmpty) return const SizedBox.shrink();

    final tone = context.v2.caution;
    final card = Container(
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
        boxShadow: V2Shadows.sm,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: tone),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(V2Spacing.space16),
                color: tone.withValues(alpha: 0.06),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: tone,
                    ),
                    const SizedBox(width: V2Spacing.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PGEyebrow('Heavy metal risk', color: tone),
                          const SizedBox(height: V2Spacing.space4),
                          Text(
                            metals.join(' · '),
                            style: V2Typography.bodyMedium(color: context.v2.fg),
                          ),
                          if (note != null) ...[
                            const SizedBox(height: V2Spacing.space4),
                            Text(
                              note!,
                              style: V2Typography.bodySm(
                                color: context.v2.fgMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: V2Spacing.space8),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: tone,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: card,
      ),
    );
  }
}
