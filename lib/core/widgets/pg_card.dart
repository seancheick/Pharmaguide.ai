import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Variants for [PGCard].
///
/// ### App-wide surface tier system (4 tiers)
///
/// Every visible *standalone* surface on a screen must map to exactly one
/// of these four tiers. Maintaining strict tiering is what gives the app
/// its first-party feel — calm hierarchy, no competing surfaces, no
/// bespoke `Container + BoxDecoration` for visible chrome.
///
/// | Tier | Variant | Cardinality | Use |
/// |---|---|---|---|
/// | **hero** | (bespoke gradient — not a PGCard variant) | **1 per screen** | The dominant primary action. e.g. home_scan_cta. |
/// | **standard** | [plain] / [elevated] | many | Default for any standalone content card. |
/// | **accent** | [highlighted] | **0–1 per screen** | A single soft brand-tinted nudge that wants attention but isn't blocking. |
/// | **recessed** | [recessed] | many | Quieter content (empty states, supporting panels). |
///
/// **Cardinality rules** are part of the contract — more than one accent
/// surface on a screen creates competing emphasis and is the most common
/// way home pages drift toward "busy" instead of "premium". If you need a
/// second emphasized surface, pick one and demote the other to [plain].
///
/// **Intra-card layout primitives** (a `Container` with `BoxDecoration`
/// *inside* an already-tiered PGCard — section dividers, tinted info
/// chips, metric strips) are NOT a fifth tier. They are layout building
/// blocks of the parent card. The tier rule applies to standalone
/// surfaces.
enum PGCardVariant {
  /// Standard tier (default) — `surfaceContainer` + soft outline. Use for
  /// any standalone content card with no special emphasis.
  plain,

  /// Standard tier with subtle drop shadow — for content that should feel
  /// physically above the page (featured items, hero panels).
  elevated,

  /// **Accent tier** — brand-tinted highlight. Reserved for the single
  /// most important callout on a screen (max 1 per screen). No outline,
  /// brand primary at low alpha. If you find yourself wanting two of
  /// these on one screen, demote one to [plain].
  highlighted,

  /// **Recessed tier** — `surfaceContainerLow`, no outline. Use for
  /// quieter supporting content (empty states, info panels, nested
  /// groupings inside an existing card).
  recessed,
}

/// A premium card surface.
///
/// Use this instead of raw `Container + BoxDecoration` or `Card`. Delivers
/// consistent radius, outline, tap feedback, and dark-mode handling in one
/// place — which is the difference between a design system and scattered
/// styles.
///
/// ```dart
/// PGCard(
///   onTap: () => context.push('/product/$id'),
///   child: Column(...),
/// )
/// ```
class PGCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final PGCardVariant variant;

  /// For [PGCardVariant.highlighted] — overrides the brand tint.
  final Color? tintColor;

  /// Override default radius (`AppTheme.radiusLarge`).
  final BorderRadius? borderRadius;

  const PGCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.space16),
    this.onTap,
    this.onLongPress,
    this.variant = PGCardVariant.plain,
    this.tintColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(AppTheme.radiusLarge);

    late final Color bg;
    late final List<BoxShadow> shadow;
    late final BoxBorder? border;

    switch (variant) {
      case PGCardVariant.plain:
        bg = scheme.surfaceContainer;
        shadow = AppElevation.none;
        border = Border.all(color: scheme.outlineVariant, width: 0.8);
        break;
      case PGCardVariant.elevated:
        bg = scheme.surfaceContainer;
        shadow = AppElevation.low;
        border = Border.all(color: scheme.outlineVariant, width: 0.8);
        break;
      case PGCardVariant.highlighted:
        final tint = tintColor ?? scheme.primary;
        bg = tint.withValues(alpha: isDark ? 0.16 : 0.08);
        shadow = AppElevation.none;
        border = null;
        break;
      case PGCardVariant.recessed:
        bg = scheme.surfaceContainerLow;
        shadow = AppElevation.none;
        border = null;
        break;
    }

    final decoration = BoxDecoration(
      color: bg,
      borderRadius: radius,
      border: border,
      boxShadow: shadow,
    );

    final body = Padding(padding: padding, child: child);

    if (onTap == null && onLongPress == null) {
      return AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.standard,
        decoration: decoration,
        child: body,
      );
    }

    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.standard,
      decoration: decoration,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          splashColor: scheme.primary.withValues(alpha: 0.08),
          highlightColor: scheme.primary.withValues(alpha: 0.04),
          child: body,
        ),
      ),
    );
  }
}
