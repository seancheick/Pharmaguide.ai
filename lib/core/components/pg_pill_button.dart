import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 button variants.
enum PGPillVariant {
  /// Solid accent fill. Use for the single primary CTA per surface.
  primary,

  /// Outline border, accent text. Use for secondary actions.
  secondary,

  /// Text-only, no border. Use for tertiary / inline actions.
  ghost,
}

/// Pill-shaped CTA mirroring the website's primary action style.
///
/// Cardinality: **one [PGPillVariant.primary] per visible surface.**
/// More than one and the hierarchy collapses.
///
/// Hover/press uplifts the shadow to [V2Shadows.accentGlow] (primary only).
/// All transitions are interruptible per the performance contract.
class PGPillButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final PGPillVariant variant;

  /// Stretches to fill horizontal space when true.
  final bool expand;

  const PGPillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = PGPillVariant.primary,
    this.expand = false,
  });

  @override
  State<PGPillButton> createState() => _PGPillButtonState();
}

class _PGPillButtonState extends State<PGPillButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final isPrimary = widget.variant == PGPillVariant.primary;
    final isSecondary = widget.variant == PGPillVariant.secondary;

    final bg = switch (widget.variant) {
      PGPillVariant.primary =>
        disabled ? V2Colors.accent.withValues(alpha: 0.5) : V2Colors.accent,
      PGPillVariant.secondary => Colors.transparent,
      PGPillVariant.ghost => Colors.transparent,
    };

    final fg = switch (widget.variant) {
      PGPillVariant.primary => Colors.white,
      PGPillVariant.secondary || PGPillVariant.ghost => V2Colors.accent,
    };

    final border = isSecondary
        ? BorderSide(color: V2Colors.accent.withValues(alpha: 0.4))
        : BorderSide.none;

    final shadow = isPrimary && _pressed && !disabled
        ? V2Shadows.accentGlow
        : (isPrimary && !disabled ? V2Shadows.sm : V2Shadows.none);

    final child = AnimatedContainer(
      duration: V2Motion.fast,
      curve: V2Motion.smooth,
      padding: EdgeInsets.symmetric(
        horizontal: widget.icon != null ? V2Spacing.space16 : V2Spacing.space24,
        vertical: V2Spacing.space12,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        border: Border.fromBorderSide(border),
        boxShadow: shadow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 18, color: fg),
            const SizedBox(width: V2Spacing.space8),
          ],
          Text(widget.label, style: V2Typography.label(color: fg)),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: disabled ? null : (_) => _setPressed(true),
        onTapUp: disabled ? null : (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onPressed,
        child: widget.expand
            ? SizedBox(width: double.infinity, child: child)
            : child,
      ),
    );
  }
}
