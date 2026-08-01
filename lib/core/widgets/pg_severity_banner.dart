import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Severity levels for [PGSeverityBanner] — independent from the clinical
/// `Severity` enum because banners can also surface neutral info/warning
/// states that aren't tied to interaction data.
enum PGBannerTone {
  /// Teal info — "here's something you should know, but nothing wrong".
  info,

  /// Amber caution — "pay attention, this matters but isn't blocking".
  caution,

  /// Red danger — "this is unsafe / blocking / contraindicated".
  danger,

  /// Green success — "verified safe / all clear".
  success,

  /// Indigo neutral — "not enough data" / "insufficient".
  neutral,
}

/// Full-width severity banner — the card you use to tell the user something
/// important at the top of a screen. Replaces ad-hoc `Container + Border.all`
/// warning banners throughout the app.
///
/// Tinted surface fill + left accent strip + icon + title + optional body.
/// No loud red boxes; the severity is communicated by tone, not volume.
///
/// ```dart
/// PGSeverityBanner(
///   tone: PGBannerTone.caution,
///   title: 'Your kidney condition affects this product',
///   body: 'Magnesium citrate requires dose adjustment for reduced eGFR.',
///   actionLabel: 'Learn more',
///   onAction: () => _showDetails(),
/// )
/// ```
class PGSeverityBanner extends StatelessWidget {
  final PGBannerTone tone;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry margin;

  const PGSeverityBanner({
    super.key,
    required this.tone,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.margin = EdgeInsets.zero,
  });

  // Takes the palette rather than a BuildContext: this helper needs
  // colours, not the element tree.
  ({Color accent, IconData icon}) _style(V2Palette p) {
    switch (tone) {
      case PGBannerTone.info:
        return (accent: p.accent, icon: Icons.info_outline_rounded);
      case PGBannerTone.caution:
        return (accent: p.caution, icon: Icons.warning_amber_rounded);
      case PGBannerTone.danger:
        return (accent: p.contraindicated, icon: Icons.block_rounded);
      case PGBannerTone.success:
        return (
          accent: p.safe,
          icon: Icons.check_circle_outline_rounded,
        );
      case PGBannerTone.neutral:
        return (accent: p.fgMuted, icon: Icons.help_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.v2;
    final style = _style(palette);
    final tint = style.accent.withValues(alpha: isDark ? 0.14 : 0.06);

    // These were `const`, so they could not react to brightness even in
    // principle — the banner stayed a bright card on a dark screen.
    final surfaceColor = palette.surface;
    final outlineColor = palette.outline;
    final mutedColor = palette.fgMuted;
    const horizontalPadding = V2Spacing.space16;
    const verticalPadding = V2Spacing.space12;
    const iconGap = V2Spacing.space12;
    const bodyGap = V2Spacing.space4;
    const actionGap = V2Spacing.space8;
    const chevronGap = 2.0;
    const actionRadius = V2Spacing.radiusPill;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: outlineColor, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Severity wash
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [tint, Colors.transparent],
                  stops: const [0.0, 0.5],
                ),
              ),
            ),
          ),
          // Left accent strip
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: style.accent),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              horizontalPadding + 3,
              verticalPadding,
              horizontalPadding,
              verticalPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(style.icon, size: 20, color: style.accent),
                const SizedBox(width: iconGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: V2Typography.titleSm(color: palette.fg),
                      ),
                      if (body != null && body!.isNotEmpty) ...[
                        const SizedBox(height: bodyGap),
                        Text(
                          body!,
                          style: V2Typography.bodySm(color: mutedColor),
                        ),
                      ],
                      if (actionLabel != null && onAction != null) ...[
                        const SizedBox(height: actionGap),
                        InkWell(
                          onTap: onAction,
                          borderRadius: BorderRadius.circular(actionRadius),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  actionLabel!,
                                  style: V2Typography.label(
                                    color: style.accent,
                                  ),
                                ),
                                const SizedBox(width: chevronGap),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: style.accent,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
