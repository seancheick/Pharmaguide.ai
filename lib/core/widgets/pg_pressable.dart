import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';

/// Apple-style press feedback wrapper.
///
/// Scales the child to [pressedScale] (default 0.96) on press-in and
/// spring-releases to 1.0 on lift, while firing [PGHaptics.press] on tap
/// confirmation. This is the iOS tactile signature on every tappable
/// surface — the press-down compression that App Store, Apple TV, and the
/// home grid use on every tile.
///
/// Use this for any tappable card, tile, or button where you want the
/// iOS feel instead of the Material `InkWell` ripple. For heavily
/// interactive surfaces with rich tap visuals (e.g. selection states),
/// wrap the visual layer with [PGPressable] and keep your own InkWell
/// for the secondary state.
///
/// ```dart
/// PGPressable(
///   onTap: () => context.push('/product/$id'),
///   child: YourCardSurface(child: ...),
/// )
/// ```
///
/// **Accessibility:** Honors `MediaQueryData.disableAnimations` (system
/// reduce-motion). Under reduce-motion the scale animation is skipped
/// entirely — the tap still fires. Haptic also honors reduce-motion via
/// [PGHaptics.press] which suppresses decorative haptics in that case.
///
/// **No-op when not interactive:** if both [onTap] and [onLongPress] are
/// null, no gesture detection runs and no animation triggers — useful
/// for conditionally interactive surfaces (e.g. a card that becomes
/// tappable only after data loads).
class PGPressable extends StatefulWidget {
  final Widget child;

  /// Called on tap-up after a successful tap (not on tap-down).
  final VoidCallback? onTap;

  /// Called on long-press. When set, swallows the tap so [onTap] does
  /// NOT fire on the same gesture.
  final VoidCallback? onLongPress;

  /// Scale at the bottom of the press. Default 0.96 — matches App Store /
  /// Apple TV tile press depth. Use 0.92 for hero CTAs that should feel
  /// more dramatic, 0.99 for very subtle (e.g. menu items).
  final double pressedScale;

  /// Whether to fire [PGHaptics.press] on tap. Default true. Disable for
  /// very frequent taps (e.g. keyboard rows) to avoid haptic fatigue.
  final bool haptic;

  /// Border radius of the keyboard-focus ring. Defaults to
  /// `V2Spacing.radiusCard`. Pass a custom value when wrapping a
  /// non-card-shaped child (e.g. a pill chip → `radiusPill`).
  /// The ring only paints under keyboard / screen-reader focus, so
  /// touch-only sessions never see it — safe to leave on the default.
  final BorderRadius? focusBorderRadius;

  const PGPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.haptic = true,
    this.focusBorderRadius,
  });

  @override
  State<PGPressable> createState() => _PGPressableState();
}

class _PGPressableState extends State<PGPressable> {
  bool _pressed = false;
  bool _focused = false;

  void _setPressed(bool v) {
    if (_pressed != v && mounted) {
      setState(() => _pressed = v);
    }
  }

  void _setFocused(bool v) {
    if (_focused != v && mounted) {
      setState(() => _focused = v);
    }
  }

  bool get _isInteractive => widget.onTap != null || widget.onLongPress != null;

  void _activate() {
    if (widget.onTap == null) return;
    if (widget.haptic) PGHaptics.press(context);
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final shouldScale = _pressed && !reduceMotion;

    final scaled = AnimatedScale(
      scale: shouldScale ? widget.pressedScale : 1.0,
      // Press-down is fast and decisive (standard ease-out); release
      // uses the gentleRelease curve — pure ease-out, zero overshoot.
      // iOS press-up has a near-zero rebound; AppMotion.spring (with
      // its 15% overshoot) is reserved for state flips / toggles where
      // a touch of bounce adds personality.
      duration: _pressed ? AppMotion.fast : AppMotion.medium,
      curve: _pressed ? AppMotion.standard : AppMotion.gentleRelease,
      child: widget.child,
    );

    if (!_isInteractive) {
      return scaled;
    }

    final scheme = Theme.of(context).colorScheme;
    final ringRadius =
        widget.focusBorderRadius ?? BorderRadius.circular(V2Spacing.radiusCard);

    // Focus ring overlay — paints only under keyboard / screen-reader
    // focus (gated by `onShowFocusHighlight`), so iPad-with-keyboard, web,
    // and accessibility users get a visible focus indicator while
    // touch-only sessions stay clean. `Positioned.fill` + `IgnorePointer`
    // means the ring overlays the child's bounds without affecting layout
    // or stealing hits. Uses `DecoratedBox` (not `Container`) so callers
    // that introspect their own widget trees in tests aren't tripped up
    // by an extra `Container` in the descendants.
    final visual = Stack(
      children: [
        scaled,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              opacity: _focused ? 1.0 : 0.0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: ringRadius,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return FocusableActionDetector(
      enabled: _isInteractive,
      onShowFocusHighlight: _setFocused,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap == null ? null : _activate,
        onLongPress: widget.onLongPress,
        child: visual,
      ),
    );
  }
}
