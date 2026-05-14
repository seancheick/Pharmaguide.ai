import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_severity_badge.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One ingredient row — name + optional dose + optional severity hint.
///
/// Compact. Designed to live inside [PGIngredientStack]. Never used in a
/// full-width vertical tile list (anti-pattern from the audit).
///
/// Severity tint applies ONLY when [severity] is set. Use sparingly: most
/// active ingredients have no severity context and should render without
/// any color decoration.
class PGIngredientChip extends StatelessWidget {
  final String name;

  /// e.g. "500 mg", "2 g". Renders in Geist Mono right-aligned.
  final String? dose;

  /// Optional severity hint — adds a colored leading dot. Use for
  /// flagged inactive ingredients (e.g. mercury, titanium dioxide).
  final PGSeverity? severity;

  /// When true, the chip taps to open an explain sheet. Pass via parent.
  final VoidCallback? onTap;

  const PGIngredientChip({
    super.key,
    required this.name,
    this.dose,
    this.severity,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tintBackground = severity?.tint;
    final dotColor = severity?.color;

    final inner = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space12,
        vertical: V2Spacing.space12,
      ),
      decoration: BoxDecoration(
        color: tintBackground ?? V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
      ),
      child: Row(
        children: [
          if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: V2Spacing.space8),
          ],
          Expanded(
            child: Text(
              name,
              style: V2Typography.bodyMedium(color: V2Colors.fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (dose != null) ...[
            const SizedBox(width: V2Spacing.space12),
            Text(
              dose!,
              style: V2Typography.monoData(color: V2Colors.fgMuted),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return inner;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        child: inner,
      ),
    );
  }
}
