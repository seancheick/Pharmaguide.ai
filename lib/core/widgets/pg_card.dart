import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';

/// Variants for [PGCard].
enum PGCardVariant {
  /// Standard card — `surfaceContainer` + soft outline. The default.
  plain,

  /// Same as plain but with a subtle drop shadow for content that should
  /// feel physically above the page (featured items, hero panels).
  elevated,

  /// Brand-tinted highlight — for the single most important callout on a
  /// screen. No outline, brand primary at low alpha.
  highlighted,

  /// Recessed — `surfaceContainerLow`, no outline. Use for nested groupings
  /// inside an existing card (settings rows, inline info panels).
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
