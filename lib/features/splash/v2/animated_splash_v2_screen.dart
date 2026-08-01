import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_halo_background.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 animated splash — editorial brand moment.
///
/// Replaces the legacy [AnimatedSplashScreen]. Visual direction:
/// - First frame: logo fully visible and screen-centered so it can
///   match the native launch screen without a layout jump.
/// - Entrance: logo glides into the upper third with a restrained scale
///   settle while the wordmark, tagline, and activity cue reveal below.
/// - Warm cream/dark background with a single low-intensity halo.
///
/// Phase 11.7L.B.6 — Sean 2026-05-16: dropped the "Calm clinical
/// intelligence." Newsreader tagline. The serif positioning line
/// over-explained the brand on a screen the user sees for ~900ms;
/// the wordmark + animated underline carry the brand moment on
/// their own. Stagger collapses from 3 steps to 2 — no other
/// timing change so the perceived pace stays consistent.
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
  bool _exiting = false;
  Timer? _startTimer;
  Timer? _exitTimer;

  static const double _logoSize = 132;
  static const double _minLogoScale = 0.98;

  /// Total entrance duration when not overridden.
  static const _defaultDuration = Duration(milliseconds: 980);

  static const _handoffDelay = Duration(milliseconds: 64);

  /// How long the composed splash holds before auto-navigating.
  static const _hold = Duration(milliseconds: 100);

  static const _exitFade = Duration(milliseconds: 160);

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
      _startTimer = Timer(_handoffDelay, () {
        if (!mounted) return;
        _ctrl.forward().whenComplete(_scheduleNext);
      });
    }
  }

  void _scheduleNext({bool reducedMotion = false}) {
    if (!widget.autoNavigate) return;
    final delay = reducedMotion ? const Duration(milliseconds: 180) : _hold;
    _exitTimer = Timer(delay, () {
      if (!mounted) return;
      if (!reducedMotion) {
        setState(() => _exiting = true);
      }
      _exitTimer = Timer(reducedMotion ? Duration.zero : _exitFade, _goNext);
    });
  }

  void _goNext() {
    if (!mounted) return;
    GoRouter.of(context).go(widget.nextRoute);
  }

  double _logoScale(double logoProgress) {
    if (logoProgress < 0.82) {
      return lerpDouble(1, _minLogoScale, logoProgress / 0.82)!;
    }
    final settleProgress = ((logoProgress - 0.82) / 0.18).clamp(0.0, 1.0);
    return lerpDouble(
      _minLogoScale,
      1,
      Curves.easeOutCubic.transform(settleProgress),
    )!;
  }

  void _cancelTimers() {
    _startTimer?.cancel();
    _exitTimer?.cancel();
  }

  @override
  void dispose() {
    _cancelTimers();
    _ctrl.dispose();
    super.dispose();
  }

  double _interval(double start, double end) {
    final local = ((_ctrl.value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(local);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final background = context.v2.bg;
    final foreground = context.v2.fg;
    final muted = context.v2.fgMuted;
    final accent = context.v2.accent;

    return AnimatedOpacity(
      opacity: _exiting ? 0 : 1,
      duration: _exitFade,
      curve: Curves.easeOutCubic,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: background,
          systemNavigationBarIconBrightness: dark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: background,
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [background, context.v2.surfaceLow],
              ),
            ),
            child: PGHaloBackground(
              origin: const Alignment(0, -0.38),
              radius: 0.92,
              intensity: dark ? 0.10 : 0.06,
              color: accent,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final logoProgress = Curves.easeOutCubic.transform(
                    _ctrl.value,
                  );
                  final wordmarkProgress = _interval(0.12, 0.52);
                  final taglineProgress = _interval(0.16, 0.58);
                  final cueProgress = _interval(0.36, 0.76);

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final centerY = constraints.maxHeight / 2;
                      final topPadding = MediaQuery.paddingOf(context).top;
                      final finalCenterY = (constraints.maxHeight * 0.34).clamp(
                        topPadding + (_logoSize / 2) + V2Spacing.space24,
                        centerY,
                      );
                      final logoLift = centerY - finalCenterY;
                      final logoScale = _logoScale(logoProgress);
                      final contentTop =
                          finalCenterY + (_logoSize / 2) + V2Spacing.space24;

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: Transform.translate(
                              offset: Offset(0, -logoLift * logoProgress),
                              child: Transform.scale(
                                scale: logoScale,
                                child: Opacity(
                                  opacity: 1,
                                  child: Image.asset(
                                    'assets/images/splash_logo.png',
                                    width: _logoSize,
                                    height: _logoSize,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: contentTop,
                            left: V2Spacing.space32,
                            right: V2Spacing.space32,
                            child: _SplashCopy(
                              wordmarkProgress: wordmarkProgress,
                              taglineProgress: taglineProgress,
                              cueProgress: cueProgress,
                              foreground: foreground,
                              muted: muted,
                              accent: accent,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashCopy extends StatelessWidget {
  final double wordmarkProgress;
  final double taglineProgress;
  final double cueProgress;
  final Color foreground;
  final Color muted;
  final Color accent;

  const _SplashCopy({
    required this.wordmarkProgress,
    required this.taglineProgress,
    required this.cueProgress,
    required this.foreground,
    required this.muted,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: wordmarkProgress,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - wordmarkProgress)),
            child: PGEyebrow('PharmaGuide', color: foreground),
          ),
        ),
        const SizedBox(height: V2Spacing.space8),
        Opacity(
          opacity: taglineProgress,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - taglineProgress)),
            child: Text(
              'Scan with confidence',
              textAlign: TextAlign.center,
              style: V2Typography.body(color: muted).copyWith(height: 1.25),
            ),
          ),
        ),
        const SizedBox(height: V2Spacing.space16),
        Opacity(
          opacity: cueProgress,
          child: _LoadingCue(color: accent),
        ),
      ],
    );
  }
}

class _LoadingCue extends StatelessWidget {
  final Color color;

  const _LoadingCue({required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(
        width: 44,
        height: 4,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.58,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
