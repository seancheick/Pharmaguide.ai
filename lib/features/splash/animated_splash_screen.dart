import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Animated splash intro — the bridge between the native splash
/// (handled by `flutter_native_splash`) and the first content screen.
///
/// Native splash → animated splash (520ms subtle settle) → next route.
/// Native and animated splash share the same brand-teal background and
/// the same logo image (`assets/images/splash_logo.png`) so the
/// hand-off is pixel-perfect: the user sees a single continuous brand
/// moment.
///
/// Premium philosophy: the logo should never disappear or pop. It
/// settles from 96% → 100% scale and 92% → 100% opacity — barely
/// perceptible motion that signals polish without drawing attention.
/// No haptic on open (haptics respond to user action, not app launch).
/// Soft dimensional gradient instead of flat background. Subtle logo
/// shadow for depth.
///
/// Reduce-motion (Accessibility → Reduce Motion) suppresses the
/// animation and jumps straight to the next route after a 180ms
/// brand-impression delay.
///
/// Spec: docs/superpowers/plans/2026-04-28-app-wide-apple-grade.md (G.1)
class AnimatedSplashScreen extends StatefulWidget {
  /// The route to navigate to once the splash animation completes.
  /// Defaults to '/' (home) if not provided. Passed in via the route's
  /// `next` query parameter.
  final String nextRoute;

  const AnimatedSplashScreen({super.key, this.nextRoute = '/'});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  bool _reduceMotionChecked = false;

  // Dimensional brand gradient — barely visible tonal shift that makes
  // the flat teal feel more premium without changing the brand color.
  static const _gradientColors = [
    Color(0xFF0B8A79),
    Color(0xFF0A7D6F),
    Color(0xFF076B60),
  ];

  // Logo display size. Picked so the animated logo lands at roughly the
  // same visible size as the native-splash logo across iPhone form
  // factors (the native splash auto-scales by density, this one is fixed
  // — 180pt is the empirically-good middle ground on a 414pt phone).
  static const double _logoSize = 180;

  // Duration: 520ms feels sharper than 600ms while still registering
  // as a brand moment.
  static const Duration _animationDuration = Duration(milliseconds: 520);
  static const Duration _reducedMotionDelay = Duration(milliseconds: 180);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );
    // Subtle settle — logo never disappears, just refines into place.
    _scale = Tween<double>(
      begin: 0.96,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotionChecked) return;
    _reduceMotionChecked = true;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      // Skip the animation; brief brand-impression delay before navigating.
      Future.delayed(_reducedMotionDelay, _goNext);
    } else {
      _ctrl.forward().then((_) => _goNext());
    }
  }

  void _goNext() {
    if (!mounted) return;
    GoRouter.of(context).go(widget.nextRoute);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0A7D6F),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _gradientColors,
            ),
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return Opacity(
                  opacity: _fade.value,
                  child: Transform.scale(
                    scale: _scale.value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/splash_logo.png',
                        width: _logoSize,
                        height: _logoSize,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
