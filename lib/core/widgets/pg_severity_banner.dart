import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
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

  /// When true, the banner resolves through V2Colors + V2Typography
  /// instead of legacy AppTheme + theme.textTheme. Callers in the
  /// v2 surfaces flip this so the banner stays cohesive with the
  /// cream bg and Geist Sans 500 hierarchy. Default false keeps
  /// every legacy call site byte-identical until Phase 11.6.
  final bool useV2Tones;

  const PGSeverityBanner({
    super.key,
    required this.tone,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.margin = EdgeInsets.zero,
    this.useV2Tones = false,
  });

  ({Color accent, IconData icon}) _style() {
    if (useV2Tones) {
      switch (tone) {
        case PGBannerTone.info:
          return (accent: V2Colors.accent, icon: Icons.info_outline_rounded);
        case PGBannerTone.caution:
          return (
            accent: V2Colors.caution,
            icon: Icons.warning_amber_rounded,
          );
        case PGBannerTone.danger:
          return (
            accent: V2Colors.contraindicated,
            icon: Icons.block_rounded,
          );
        case PGBannerTone.success:
          return (
            accent: V2Colors.safe,
            icon: Icons.check_circle_outline_rounded,
          );
        case PGBannerTone.neutral:
          return (
            accent: V2Colors.fgMuted,
            icon: Icons.help_outline_rounded,
          );
      }
    }
    switch (tone) {
      case PGBannerTone.info:
        return (accent: AppTheme.info, icon: Icons.info_outline_rounded);
      case PGBannerTone.caution:
        return (
          accent: AppTheme.severityCaution,
          icon: Icons.warning_amber_rounded,
        );
      case PGBannerTone.danger:
        return (
          accent: AppTheme.severityContraindicated,
          icon: Icons.block_rounded,
        );
      case PGBannerTone.success:
        return (
          accent: AppTheme.severitySafe,
          icon: Icons.check_circle_outline_rounded,
        );
      case PGBannerTone.neutral:
        return (
          accent: AppTheme.insufficientData,
          icon: Icons.help_outline_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final style = _style();
    final tint = style.accent.withValues(alpha: isDark ? 0.14 : 0.06);

    final surfaceColor = useV2Tones ? V2Colors.surface : scheme.surfaceContainer;
    final outlineColor = useV2Tones ? V2Colors.outline : scheme.outlineVariant;
    final mutedColor = useV2Tones ? V2Colors.fgMuted : scheme.onSurfaceVariant;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(
          useV2Tones ? V2Spacing.radiusCard : AppTheme.radiusLarge,
        ),
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
              AppTheme.space16 + 3,
              AppTheme.space12,
              AppTheme.space16,
              AppTheme.space12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(style.icon, size: 20, color: style.accent),
                const SizedBox(width: AppTheme.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: useV2Tones
                            ? V2Typography.titleSm(color: V2Colors.fg)
                            : theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                      ),
                      if (body != null && body!.isNotEmpty) ...[
                        const SizedBox(height: AppTheme.space4),
                        Text(
                          body!,
                          style: useV2Tones
                              ? V2Typography.bodySm(color: mutedColor)
                              : theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.45,
                                ),
                        ),
                      ],
                      if (actionLabel != null && onAction != null) ...[
                        const SizedBox(height: AppTheme.space8),
                        InkWell(
                          onTap: onAction,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusFull,
                          ),
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
                                  style: useV2Tones
                                      ? V2Typography.label(color: style.accent)
                                      : theme.textTheme.labelLarge?.copyWith(
                                          fontSize: 13,
                                          color: style.accent,
                                        ),
                                ),
                                const SizedBox(width: AppTheme.space2),
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
