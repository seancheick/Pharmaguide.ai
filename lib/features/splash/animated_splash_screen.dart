import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/widgets/pg_haptics.dart';

/// Animated splash intro — the bridge between the native splash
/// (handled by `flutter_native_splash`) and the first content screen.
///
/// Native splash → animated splash (600ms scale-up + fade-in) → next
/// route. Native and animated splash share the same brand-teal
/// background (`#0A7D6F`) and the same logo image
/// (`assets/images/splash_logo.png`) so the hand-off is pixel-perfect:
/// the user sees a single continuous brand moment.
///
/// Reduce-motion (Accessibility → Reduce Motion) suppresses the
/// scale + fade and jumps straight to the next route after a 200ms
/// brand-impression delay (just enough to register the brand, no
/// animation).
///
/// At the end of the animation, fires `PGHaptics.tap(context)` —
/// Apple's signature "we noticed you arrived" detail.
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

  // Brand teal — must match flutter_native_splash:color in pubspec.yaml.
  static const Color _splashBackground = Color(0xFF0A7D6F);

  // Logo display size. Picked so the animated logo lands at roughly the
  // same visible size as the native-splash logo across iPhone form
  // factors (the native splash auto-scales by density, this one is fixed
  // — 180pt is the empirically-good middle ground on a 414pt phone).
  static const double _logoSize = 180;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: AppMotion.standard),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotionChecked) return;
    _reduceMotionChecked = true;
    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      // Skip the animation; brief brand-impression delay before navigating.
      Future.delayed(const Duration(milliseconds: 200), _goNext);
    } else {
      _ctrl.forward().then((_) {
        // Tiny haptic tick at the end of the animation — Apple's
        // signature "we noticed you arrived" detail. Decorative;
        // PGHaptics.tap is suppressed under reduce-motion (already
        // handled inside PGHaptics).
        PGHaptics.tap(context);
        _goNext();
      });
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
        systemNavigationBarColor: _splashBackground,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _splashBackground,
        body: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Opacity(
                opacity: _fade.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: Image.asset(
                    'assets/images/splash_logo.png',
                    width: _logoSize,
                    height: _logoSize,
                    // High filter quality — the logo is the focal point
                    // and we don't want bilinear softness on retina.
                    filterQuality: FilterQuality.high,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
