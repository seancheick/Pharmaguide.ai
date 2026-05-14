import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_halo_background.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 animated splash — editorial brand moment.
///
/// Replaces the legacy [AnimatedSplashScreen]. Visual direction:
/// - Warm cream background (`V2Colors.bg`) — not a teal block.
/// - Subtle radial halo above the logo, very low intensity.
/// - Logo at refined size with no drop-shadow (the warm bg already
///   gives it presence — shadows on cream read as a Material 3 demo).
/// - Below the logo: serif positioning tagline ("Calm clinical
///   intelligence.") in Newsreader 24pt — the website's voice.
/// - Below the tagline: mono-caps wordmark + thin accent underline.
/// - Sequential reveal: logo → tagline → wordmark, each ~80ms apart,
///   each fading in over 420ms with a slight upward lift.
///
/// Reduce-motion (accessibility) suppresses the staggered reveal and
/// shows the final composed state after a brief brand-impression delay.
///
/// **Why no scale-pop / drop-shadow / vertical teal gradient?** The
/// website doesn't lead with bold blocks of color — it leads with
/// editorial restraint. A premium clinical app's first frame should
/// feel like opening a medical journal, not booting a fitness tracker.
class AnimatedSplashV2Screen extends StatefulWidget {
  /// Route to navigate to once the splash completes.
  final String nextRoute;

  /// Optional override for the total entrance duration. When null,
  /// the screen uses the computed total (~900ms including stagger).
  final Duration? entranceOverride;

  /// When true, navigation after the entrance is suppressed — used by
  /// the dev gallery so the splash can be inspected without auto-routing.
  final bool autoNavigate;

  const AnimatedSplashV2Screen({
    super.key,
    this.nextRoute = '/',
    this.entranceOverride,
    this.autoNavigate = true,
  });

  @override
  State<AnimatedSplashV2Screen> createState() => _AnimatedSplashV2ScreenState();
}

class _AnimatedSplashV2ScreenState extends State<AnimatedSplashV2Screen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _reduceMotionChecked = false;

  /// Stagger steps as a fraction of the controller's total duration.
  /// Each step begins fading in at its t0 fraction.
  static const _step0Logo = 0.05;
  static const _step1Tagline = 0.30;
  static const _step2Wordmark = 0.55;

  /// Fade duration as a fraction of the controller's total.
  static const _fadeFraction = 0.35;

  /// Total entrance duration when not overridden.
  static const _defaultDuration = Duration(milliseconds: 900);

  /// How long the composed splash holds before auto-navigating.
  static const _hold = Duration(milliseconds: 320);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.entranceOverride ?? _defaultDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotionChecked) return;
    _reduceMotionChecked = true;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _ctrl.value = 1;
      _scheduleNext(reducedMotion: true);
    } else {
      _ctrl.forward().whenComplete(_scheduleNext);
    }
  }

  void _scheduleNext({bool reducedMotion = false}) {
    if (!widget.autoNavigate) return;
    final delay = reducedMotion
        ? const Duration(milliseconds: 180)
        : _hold;
    Future.delayed(delay, () {
      if (!mounted) return;
      GoRouter.of(context).go(widget.nextRoute);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Compute opacity + vertical-lift offset for a stagger step.
  ({double opacity, double lift}) _stepValues(double startFraction) {
    final t = _ctrl.value;
    final localProgress =
        ((t - startFraction) / _fadeFraction).clamp(0.0, 1.0);
    // Decelerate curve — feels like content settling into place.
    final eased = V2Motion.decelerate.transform(localProgress);
    return (opacity: eased, lift: 12 * (1 - eased));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: V2Colors.bg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: V2Colors.bg,
        body: PGHaloBackground(
          // Halo sits above the logo, fading downward — gives the screen
          // a single soft focal point without competing with the logo.
          origin: const Alignment(0, -0.45),
          radius: 0.95,
          intensity: 0.06,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final logo = _stepValues(_step0Logo);
              final tagline = _stepValues(_step1Tagline);
              final wordmark = _stepValues(_step2Wordmark);

              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: logo.opacity,
                      child: Transform.translate(
                        offset: Offset(0, logo.lift),
                        child: Image.asset(
                          'assets/images/splash_logo.png',
                          width: 132,
                          height: 132,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space32),
                    Opacity(
                      opacity: tagline.opacity,
                      child: Transform.translate(
                        offset: Offset(0, tagline.lift),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: V2Spacing.space32,
                          ),
                          child: Text(
                            'Calm clinical intelligence.',
                            style: V2Typography.displayXs(color: V2Colors.fg),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: V2Spacing.space24),
                    Opacity(
                      opacity: wordmark.opacity,
                      child: Transform.translate(
                        offset: Offset(0, wordmark.lift),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PGEyebrow('PharmaGuide'),
                            SizedBox(height: V2Spacing.space8),
                            _AccentUnderline(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Thin centered accent underline beneath the wordmark.
class _AccentUnderline extends StatelessWidget {
  const _AccentUnderline();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 2,
      decoration: BoxDecoration(
        color: V2Colors.accent,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
