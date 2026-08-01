import 'package:flutter/material.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// One row inside a [PGSettingsGroup].
///
/// Calm, utility-focused — icon + label + optional caption + optional
/// trailing widget. Replaces Material's `ListTile` whose default padding
/// and typography are too generic.
///
/// **Variants:**
/// - Default: muted icon + sans label
/// - [destructive] true: contraindicated tint icon + label (calm muted
///   red, never bright Material error red)
class PGSettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? caption;

  /// Trailing widget (chevron, switch, badge…). When null and [onTap]
  /// is set, the tile renders a default chevron.
  final Widget? trailing;

  final VoidCallback? onTap;
  final bool destructive;

  const PGSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.caption,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = destructive ? context.v2.contraindicated : context.v2.fg;
    final iconColor = destructive ? context.v2.contraindicated : context.v2.fgMuted;
    final captionColor = destructive
        ? context.v2.contraindicated
        : context.v2.fgMuted;

    final tail =
        trailing ??
        (onTap != null
            ? Icon(
                Icons.chevron_right_rounded,
                color: context.v2.fgSubtle,
                size: 20,
              )
            : null);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space16,
          vertical: V2Spacing.space12,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: V2Spacing.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: V2Typography.bodyMedium(color: fg)),
                  if (caption != null) ...[
                    const SizedBox(height: V2Spacing.space4),
                    Text(
                      caption!,
                      style: V2Typography.bodySm(color: captionColor),
                    ),
                  ],
                ],
              ),
            ),
            if (tail != null) ...[
              const SizedBox(width: V2Spacing.space12),
              tail,
            ],
          ],
        ),
      ),
    );
  }
}

/// Grouped settings card — surface bg + hairline outline + hairline
/// separators between rows.
///
/// Use one group per logical section (Account, Privacy, etc). Pair with
/// a `PGEyebrow` above the group to label it.
class PGSettingsGroup extends StatelessWidget {
  /// Optional mono caps label rendered above the group.
  final String? eyebrow;
  final List<PGSettingsTile> children;

  const PGSettingsGroup({super.key, this.eyebrow, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space8),
            child: PGEyebrow(eyebrow!, color: context.v2.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space8),
        ],
        Material(
          color: context.v2.surface,
          borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
              border: Border.all(color: context.v2.outline),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1) const _TileDivider(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Hairline divider between settings tiles. Indented past the icon
/// column so it reads as a soft separator, not a hard rule.
class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: V2Spacing.space48),
      child: Divider(color: context.v2.outline, height: 1, thickness: 1),
    );
  }
}
