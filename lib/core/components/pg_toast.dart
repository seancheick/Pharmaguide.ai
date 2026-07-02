import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// Tone of a [PGToast] — picks the leading icon and its accent color.
enum PGToastVariant { success, info, error }

/// The single toast/snackbar for PharmaGuide v2 — a floating, rounded,
/// softly-shadowed card matching the rest of the v2 component library
/// (`PGPillButton`, `PGSeverityPill`). Use this instead of a bare
/// `SnackBar(...)` so every toast in the app looks and feels the same.
///
/// Built on top of [SnackBar] (transparent background, zero elevation,
/// zero padding, our own styled content) so it keeps Flutter's built-in
/// queueing, swipe-to-dismiss, and accessibility semantics for free —
/// only the visual chrome is custom.
abstract final class PGToast {
  /// Shows a toast anchored to [context]'s nearest [ScaffoldMessenger].
  ///
  /// [actionLabel] + [onAction] add a trailing text action (e.g. "Undo",
  /// "Go to Stack") — omit both for a plain toast.
  static void show(
    BuildContext context,
    String message, {
    PGToastVariant variant = PGToastVariant.info,
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) => showWith(
    ScaffoldMessenger.of(context),
    message,
    variant: variant,
    duration: duration,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  /// Same as [show], for call sites reached via a stored
  /// `ScaffoldMessengerState` (e.g. the root `scaffoldMessengerKey`)
  /// where there's no local BuildContext across an async gap.
  static void showWith(
    ScaffoldMessengerState? messenger,
    String message, {
    PGToastVariant variant = PGToastVariant.info,
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (messenger == null) return;
    final isDark = Theme.of(messenger.context).brightness == Brightness.dark;
    final style = _style(variant, isDark);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          content: _PGToastCard(
            message: message,
            style: style,
            actionLabel: actionLabel,
            onAction: onAction,
            messenger: messenger,
          ),
        ),
      );
  }

  static ({Color bg, Color fg, Color outline, Color iconTint, IconData icon})
  _style(PGToastVariant variant, bool isDark) {
    final bg = isDark ? V2Colors.surfaceDark : V2Colors.surface;
    final fg = isDark ? V2Colors.fgDark : V2Colors.fg;
    final outline = isDark ? V2Colors.outlineDark : V2Colors.outline;
    return switch (variant) {
      PGToastVariant.success => (
        bg: bg,
        fg: fg,
        outline: outline,
        iconTint: V2Colors.safe,
        icon: Icons.check_circle_rounded,
      ),
      PGToastVariant.info => (
        bg: bg,
        fg: fg,
        outline: outline,
        iconTint: isDark ? V2Colors.accentDark : V2Colors.accent,
        icon: Icons.info_rounded,
      ),
      PGToastVariant.error => (
        bg: bg,
        fg: fg,
        outline: outline,
        iconTint: V2Colors.avoid,
        icon: Icons.error_rounded,
      ),
    };
  }
}

class _PGToastCard extends StatelessWidget {
  final String message;
  final ({Color bg, Color fg, Color outline, Color iconTint, IconData icon})
  style;
  final String? actionLabel;
  final VoidCallback? onAction;
  final ScaffoldMessengerState messenger;

  const _PGToastCard({
    required this.message,
    required this.style,
    required this.actionLabel,
    required this.onAction,
    required this.messenger,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V2Spacing.space16,
        vertical: V2Spacing.space12,
      ),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        boxShadow: V2Shadows.md,
        border: Border.all(color: style.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 20, color: style.iconTint),
          const SizedBox(width: V2Spacing.space12),
          Flexible(
            child: Text(message, style: V2Typography.bodySm(color: style.fg)),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: V2Spacing.space12),
            InkWell(
              borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
              onTap: () {
                onAction?.call();
                messenger.hideCurrentSnackBar();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: V2Spacing.space8,
                  vertical: V2Spacing.space4,
                ),
                child: Text(
                  actionLabel!,
                  style: V2Typography.label(color: style.iconTint),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
