import 'package:flutter/material.dart';

/// Platform-consistent modal helpers.
///
/// Wraps Flutter's `showModalBottomSheet` with PharmaGuide-grade defaults:
/// scroll-controlled (sheet expands to its content), safe-area aware,
/// drag-handle visible, surface-tinted background. Centralizes the modal
/// vocabulary so any global tweak (corner radius, blur backdrop, dismiss
/// animation) lands in one place.
///
/// Note: a Cupertino-specific path was considered but skipped on
/// 2026-04-28 — `showCupertinoModalPopup` is for action sheets, not
/// content sheets, and Flutter's Material 3 `showModalBottomSheet`
/// already renders with iOS-friendly rounded corners + drag handle.
/// If we adopt iOS sheet detents in the future, the seam to plug it in
/// is right here.
abstract final class PGModal {
  /// Present [builder] as a modal bottom sheet. Returns the value passed
  /// to `Navigator.of(ctx).pop(value)` inside the sheet, or null when
  /// the user dismisses without committing.
  ///
  /// Defaults:
  /// - `isScrollControlled: true` — sheet height tracks content; child
  ///   may scroll internally.
  /// - `useSafeArea: true` — bottom inset never eats content.
  /// - `showDragHandle: true` — Material 3 grabber visible at top.
  /// - `backgroundColor: ColorScheme.surface` — neutral page material.
  /// - `constraints: BoxConstraints(maxWidth: 560)` — Material 3 modal
  ///   sheet spec. Phones (≤560pt) span full width; tablets cap at
  ///   560pt centered. Pass an explicit `constraints` to override
  ///   (e.g., a settings sheet that wants 720pt on iPad).
  ///   Spec: INITIATIVE_PRODUCT_DETAIL_CLEANUP.md S2.1 / T5.
  static Future<T?> bottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isDismissible = true,
    bool useSafeArea = true,
    bool showDragHandle = true,
    Color? backgroundColor,
    BoxConstraints? constraints,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isDismissible: isDismissible,
      useSafeArea: useSafeArea,
      showDragHandle: showDragHandle,
      isScrollControlled: true,
      backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.surface,
      constraints: constraints ?? const BoxConstraints(maxWidth: 560),
    );
  }
}
