import 'package:flutter/material.dart';
import 'package:pharmaguide/core/widgets/pg_pressable.dart';

/// Circular icon button — Apple Maps / News / Photos top-chrome pattern.
///
/// A ~38pt circular surface with a subtle outline + faint drop shadow,
/// containing a centered icon. Used by [PGFrostedAppBar] for the
/// leading back chevron and trailing actions, and anywhere else a
/// "floating circle" tap target is wanted (modal dismiss, etc.).
///
/// Press feedback via [PGPressable]: scales to 0.92 (slightly deeper
/// than the 0.96 default — small surface area benefits from more depth)
/// with a light haptic.
///
/// ```dart
/// PGCircularIconButton(
///   icon: Icons.ios_share_rounded,
///   onTap: () => _showShareSheet(context),
/// )
/// ```
class PGCircularIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  /// Outer diameter. Default 38 — Apple's iOS top-chrome icon-button size.
  final double size;

  /// Override the icon color. Defaults to `colorScheme.onSurface`.
  /// Pass a destructive red for "Remove" / "Delete" actions.
  final Color? tone;

  /// Whether to fire a tap haptic. Default true; pass false when the
  /// destination already produces a haptic on first present (e.g. iOS
  /// share sheet) to avoid double-tap.
  final bool haptic;

  const PGCircularIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 38,
    this.tone,
    this.haptic = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = tone ?? scheme.onSurface;
    return PGPressable(
      onTap: onTap,
      pressedScale: 0.92,
      haptic: haptic,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
          // Subtle drop shadow — the "3D high-end" cue. Buttons hover
          // very slightly above the page material.
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: size * 0.48, color: iconColor),
      ),
    );
  }
}
