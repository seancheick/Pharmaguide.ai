import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_halo_background.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/features/auth/v2/magic_link_sheet.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';

/// v2 Auth Invitation — the calm sign-in page that sits between
/// onboarding completion and the home screen.
///
/// Production wires Apple, Google, email magic-link, and guest skip
/// callbacks from `app.dart`. Dev previews/tests may pass null callbacks
/// when they only need the visual surface.
///
/// Editorial direction (per Sean, 2026-05-15):
/// - DO NOT use the word "beta" anywhere on this screen
/// - Pricing badge reads "Free during early access"
/// - Apple button first on iOS, Google first on Android (HIG)
/// - Magic link for email — no password, no forgot-password flow
/// - "Skip for now" stays visible and non-punitive
/// - Guest note explains the limitation without scolding
///
/// Tone: continuation of onboarding, not a paywall. A user who skips
/// should feel like they made a reasonable choice, not like they
/// dodged a wall.
class AuthInvitationV2Screen extends StatefulWidget {
  /// Callback when the user taps Continue with Apple.
  final VoidCallback? onApple;

  /// Callback when the user taps Continue with Google.
  final VoidCallback? onGoogle;

  /// Callback when the user taps Continue with Email — routes to the
  /// magic-link entry sheet.
  final VoidCallback? onEmail;

  /// Callback when the user taps Skip for now. Production: marks the
  /// session as guest, preserves onboarding completion, navigates home.
  final VoidCallback? onSkip;

  const AuthInvitationV2Screen({
    super.key,
    this.onApple,
    this.onGoogle,
    this.onEmail,
    this.onSkip,
  });

  @override
  State<AuthInvitationV2Screen> createState() => _AuthInvitationV2ScreenState();
}

class _AuthInvitationV2ScreenState extends State<AuthInvitationV2Screen>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// Slow, organic heartbeat on the brand mark. ~3.6s per cycle —
  /// matches a calm resting human pulse, slowed slightly so it reads
  /// as ambient breath, not anxious. Skipped when the OS has
  /// reduce-motion enabled.
  late final AnimationController _heartbeat;
  late final Animation<double> _heartbeatScale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      // 1400ms total entrance — with the per-element window dropped
      // to 0.20, elements now reveal sequentially with only a tiny
      // overlap, so the user sees: mark → headline → subhead →
      // buttons → skip in a clear cascade rather than a single
      // blended fade-up. Sean's call 2026-05-15: "one section
      // staggering at a time, smooth entrance one by one."
      duration: const Duration(milliseconds: 1400),
    )..forward();

    _heartbeat = AnimationController(
      vsync: this,
      // 1500ms one-way × 2 (reverse) = 3.0s full cycle. Faster than
      // the previous 4.4s so the motion is clearly perceptible
      // without becoming anxious — sits between a calm breath and
      // a resting pulse.
      duration: const Duration(milliseconds: 1500),
    );
    // Scale peak bumped 8% → 12% (1.12). At 56pt that's ~6.7px peak
    // movement, which is comfortably above the perceptual threshold.
    // Stays under 1.15 so the mark never feels like it's straining.
    _heartbeatScale = Tween<double>(
      begin: 1.0,
      end: 1.12,
    ).animate(CurvedAnimation(parent: _heartbeat, curve: Curves.easeInOutSine));
    // Defer starting the heartbeat until the stagger entrance has had
    // a moment to settle — otherwise the mark grows while it's still
    // fading in, which reads as nervous, not calm.
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _heartbeat.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _heartbeat.dispose();
    super.dispose();
  }

  /// Sequential stagger. Each element animates over 20% of the
  /// 1400ms total (= 280ms per element) starting at its
  /// [delayFraction]. Adjacent elements are spaced 0.18 apart, so
  /// the next element starts as the previous one is nearly done —
  /// a clear cascade with just enough overlap to feel smooth.
  ///
  /// Lift bumped 22 → 28 so the entrance motion is unmistakable.
  ({double opacity, double lift}) _stagger(double delayFraction) {
    final t = ((_ctrl.value - delayFraction) / 0.20).clamp(0.0, 1.0);
    final eased = V2Motion.decelerate.transform(t);
    return (opacity: eased, lift: 28 * (1 - eased));
  }

  void _noopOrCall(VoidCallback? cb) {
    // Callbacks may be null in isolated previews/tests; production
    // delegates to real route/auth handlers from app.dart.
    cb?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: v2SystemOverlay(context),
      child: Scaffold(
        body: PGHaloBackground(
          // Halo origin matches splash for emotional continuity — the
          // user has just seen the same soft accent glow on the
          // celebration screen.
          origin: const Alignment(0, -0.7),
          radius: 1.0,
          intensity: 0.05,
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                // Delays spaced 0.18 apart so each element starts as
                // the previous one is just finishing — sequential
                // cascade, not blended fade-up.
                final mark = _stagger(0.0);
                final headline = _stagger(0.18);
                final subhead = _stagger(0.36);
                final buttons = _stagger(0.54);
                final skip = _stagger(0.72);

                return LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: V2Spacing.space24,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: V2Spacing.space48),
                                _Faded(
                                  opacity: mark.opacity,
                                  lift: mark.lift,
                                  child: _BrandMark(pulse: _heartbeatScale),
                                ),
                                const SizedBox(height: V2Spacing.space32),
                                _Faded(
                                  opacity: headline.opacity,
                                  lift: headline.lift,
                                  child: const _Headline(),
                                ),
                                const SizedBox(height: V2Spacing.space16),
                                _Faded(
                                  opacity: subhead.opacity,
                                  lift: subhead.lift,
                                  child: const _Subhead(),
                                ),
                                const Spacer(),
                                _Faded(
                                  opacity: buttons.opacity,
                                  lift: buttons.lift,
                                  child: _AuthButtonStack(
                                    onApple: () => _noopOrCall(widget.onApple),
                                    onGoogle: () =>
                                        _noopOrCall(widget.onGoogle),
                                    onEmail: () => _noopOrCall(widget.onEmail),
                                  ),
                                ),
                                const SizedBox(height: V2Spacing.space24),
                                _Faded(
                                  opacity: skip.opacity,
                                  lift: skip.lift,
                                  child: _SkipFooter(
                                    onSkip: () => _noopOrCall(widget.onSkip),
                                  ),
                                ),
                                const SizedBox(height: V2Spacing.space24),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Internal pieces — kept private so the screen reads top-down.
// =============================================================================

/// Wraps a child in an opacity + lift transform — the shared stagger
/// primitive used for every entrance element on this screen.
class _Faded extends StatelessWidget {
  final double opacity;
  final double lift;
  final Widget child;
  const _Faded({
    required this.opacity,
    required this.lift,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Transform.translate(offset: Offset(0, lift), child: child),
    );
  }
}

/// Small centered logo + wordmark — the user just saw a larger version
/// on splash, this is a quieter callback. 56pt mark sits comfortably
/// without dominating the headline below.
///
/// The logo carries a slow ambient heartbeat (~3.6s cycle, 4.5% scale
/// peak) driven by [pulse] — Sean's call 2026-05-15 to give the
/// screen a calmer, breathing quality. Skipped automatically when the
/// OS reports reduce-motion.
class _BrandMark extends StatelessWidget {
  final Animation<double> pulse;
  const _BrandMark({required this.pulse});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final logo = Image.asset(
      'assets/images/splash_logo.png',
      width: 56,
      height: 56,
      filterQuality: FilterQuality.high,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reduceMotion)
          logo
        else
          AnimatedBuilder(
            animation: pulse,
            builder: (context, child) =>
                Transform.scale(scale: pulse.value, child: child),
            child: logo,
          ),
        const SizedBox(height: V2Spacing.space8),
        const PGEyebrow('PharmaGuide'),
      ],
    );
  }
}

/// Serif headline — the only Newsreader on this screen (anti-goal rule:
/// serif belongs on first-impression moments, not on every screen).
class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Save your stack before\nyour first scan.',
      style: V2Typography.displayXs(color: context.v2.fg),
      textAlign: TextAlign.center,
    );
  }
}

/// Geist Sans subhead. Locked copy — mirrors what Sean signed off on.
class _Subhead extends StatelessWidget {
  const _Subhead();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space8),
      child: Text(
        'PharmaGuide works best when your supplements, medications, '
        'and profile stay connected. Sign in to keep your stack and '
        'safety checks in sync across devices.',
        // Stepped down from bodyXl (18pt) → body (16pt) per Sean
        // 2026-05-15 — 18pt felt slightly oversized against the
        // serif headline above.
        style: V2Typography.body(color: context.v2.fgMuted),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Vertically stacked Apple / Google / Email buttons + the
/// "Free during early access" pricing badge above them.
///
/// Order: Apple first on iOS (HIG requirement — Sign in with Apple
/// must be at least as prominent as competing providers), Google
/// first on Android.
class _AuthButtonStack extends StatelessWidget {
  final VoidCallback onApple;
  final VoidCallback onGoogle;
  final VoidCallback onEmail;

  const _AuthButtonStack({
    required this.onApple,
    required this.onGoogle,
    required this.onEmail,
  });

  @override
  Widget build(BuildContext context) {
    final appleFirst = Platform.isIOS;

    final apple = _AuthButton(
      label: 'Continue with Apple',
      icon: Icons.apple_rounded,
      style: _AuthButtonStyle.appleDark,
      onPressed: onApple,
    );
    final google = _AuthButton(
      label: 'Continue with Google',
      icon: Icons.g_mobiledata_rounded,
      style: _AuthButtonStyle.googleLight,
      onPressed: onGoogle,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _EarlyAccessBadge(),
        const SizedBox(height: V2Spacing.space16),
        if (appleFirst) ...[
          apple,
          const SizedBox(height: V2Spacing.space12),
          google,
        ] else ...[
          google,
          const SizedBox(height: V2Spacing.space12),
          apple,
        ],
        const SizedBox(height: V2Spacing.space12),
        // Email uses the v2 PGPillButton primary variant — it's
        // intentionally less brand-loud than the SSO providers but
        // still feels first-class. Magic link, no password.
        PGPillButton(
          label: 'Continue with email',
          icon: Icons.mail_outline_rounded,
          variant: PGPillVariant.secondary,
          expand: true,
          onPressed: onEmail,
        ),
      ],
    );
  }
}

/// Mono-caps pricing chip. Sean's call (2026-05-15): drop "beta" — say
/// "early access" instead. The badge tells users the price may change
/// later without implying the product is incomplete.
class _EarlyAccessBadge extends StatelessWidget {
  const _EarlyAccessBadge();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: V2Spacing.space12,
          vertical: V2Spacing.space4,
        ),
        decoration: BoxDecoration(
          color: context.v2.accentTint,
          borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
          border: Border.all(color: context.v2.accent.withValues(alpha: 0.18)),
        ),
        child: Text(
          'FREE DURING EARLY ACCESS',
          style: V2Typography.overline(color: context.v2.accent),
        ),
      ),
    );
  }
}

/// Provider-styled auth button — Apple and Google have specific brand
/// requirements (black-on-white or white-on-black for Apple; white
/// surface with the multi-color G for Google). We honor the spirit
/// here in v2 tones while auth itself is handled by PGAuthService.
enum _AuthButtonStyle { appleDark, googleLight }

class _AuthButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final _AuthButtonStyle style;
  final VoidCallback onPressed;

  const _AuthButton({
    required this.label,
    required this.icon,
    required this.style,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isApple = style == _AuthButtonStyle.appleDark;
    final bg = isApple ? context.v2.fg : context.v2.surface;
    final fg = isApple ? context.v2.surface : context.v2.fg;
    final borderColor = isApple ? Colors.transparent : context.v2.outline;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(V2Spacing.radiusPill),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(width: V2Spacing.space12),
              Text(label, style: V2Typography.label(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet skip link + guest limitation note. Non-punitive copy — the
/// user is told what they trade away in guest mode without being
/// scolded.
class _SkipFooter extends StatelessWidget {
  final VoidCallback onSkip;
  const _SkipFooter({required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSkip,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: V2Spacing.space8,
              horizontal: V2Spacing.space16,
            ),
            child: Text(
              'Skip for now',
              style: V2Typography.label(color: context.v2.accent),
            ),
          ),
        ),
        const SizedBox(height: V2Spacing.space8),
        Text(
          "Skip for now if you'd rather try first. Guest mode includes "
          "3 scans per day, with no AI, saved stack, or cloud sync.",
          style: V2Typography.bodySm(color: context.v2.fgSubtle),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// =============================================================================
// Dev preview wrapper — pops back into the gallery when callbacks fire.
// =============================================================================

/// Wrapper used by the `/dev/v2/auth` route. Apple + Google buttons
/// hit the real PGAuthService; email opens the magic-link sheet;
/// the global `_AuthEventListener` in app.dart surfaces the
/// signedIn snackbar on success.
class AuthInvitationV2Preview extends StatefulWidget {
  const AuthInvitationV2Preview({super.key});

  @override
  State<AuthInvitationV2Preview> createState() =>
      _AuthInvitationV2PreviewState();
}

class _AuthInvitationV2PreviewState extends State<AuthInvitationV2Preview> {
  final _auth = PGAuthService();
  bool _busy = false;

  Future<void> _runProvider(
    Future<PGAuthResult> Function() callable,
    String label,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await callable();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case PGAuthSuccess _:
        // Global _AuthEventListener will fire the "Signed in as ..."
        // toast — nothing to show here.
        break;
      case PGAuthHandoffToBrowser _:
        PGToast.show(
          context,
          'Continuing with $label in your browser…',
          variant: PGToastVariant.info,
        );
      case PGAuthCancelled _:
        // Silent — user backed out, no noise.
        break;
      case PGAuthError(:final message):
        PGToast.show(
          context,
          message,
          variant: PGToastVariant.error,
          duration: const Duration(seconds: 3),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AuthInvitationV2Screen(
          onApple: () => _runProvider(_auth.signInWithApple, 'Apple'),
          onGoogle: () => _runProvider(_auth.signInWithGoogle, 'Google'),
          // Email is real — opens the magic-link sheet that calls
          // supabase.auth.signInWithOtp() with the pharmaguide://
          // redirect URL.
          onEmail: () => showMagicLinkSheet(context),
          onSkip: () => context.go('/dev/v2'),
        ),
        // Floating back button — gallery preview only. Production
        // doesn't show a back button on this screen (it sits in the
        // onboarding → home root-replacement flow).
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: Material(
            color: context.v2.surface,
            shape: const CircleBorder(),
            elevation: 0,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.go('/dev/v2'),
              child: Padding(
                padding: const EdgeInsets.all(V2Spacing.space8),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: context.v2.fg,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
