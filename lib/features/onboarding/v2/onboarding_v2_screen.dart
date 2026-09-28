import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';

/// First-run intro: one screen, then straight into the app.
///
/// It used to be four explainer pages (value, profile, a goals quiz, trust),
/// then a celebration, then a sign-in wall — five taps and seven screens
/// before anything useful. Approved by Sean 2026-09-28, following the HIG
/// (onboarding: "teach through interactivity", keep a prerequisite flow
/// brief; managing accounts: "delay sign-in for as long as possible"):
///
/// - one value screen: what a scan gives you, where it comes from, where
///   your data lives;
/// - **Start scanning** opens the camera; **Set up my profile first** opens
///   the guided profile wizard (it asks for goals, conditions and allergies,
///   and finishes on Home);
/// - no sign-in: the account is offered when someone wants sync, and
///   product pages nudge the profile where it changes the answer.
///
/// When [autoFinish] is false (the dev gallery preview), the buttons neither
/// persist onboarding prefs nor navigate, so the screen can be replayed.
class OnboardingV2Screen extends StatefulWidget {
  final bool autoFinish;

  const OnboardingV2Screen({super.key, this.autoFinish = true});

  @override
  State<OnboardingV2Screen> createState() => _OnboardingV2ScreenState();
}

class _OnboardingV2ScreenState extends State<OnboardingV2Screen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: V2Motion.slower)
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _finish(String route) async {
    if (!widget.autoFinish || _leaving) return;
    _leaving = true;
    await OnboardingPrefs.markSeen();
    if (!mounted) return;
    GoRouter.of(context).go(route);
  }

  /// Opacity + lift for an element starting at [delayFraction] of the
  /// entrance. Reduce Motion skips straight to the settled state.
  ({double opacity, double lift}) _stagger(
    double delayFraction, {
    required bool reduceMotion,
  }) {
    if (reduceMotion) return (opacity: 1, lift: 0);
    final t = ((_ctrl.value - delayFraction) / 0.6).clamp(0.0, 1.0);
    final eased = V2Motion.decelerate.transform(t);
    return (opacity: eased, lift: 14 * (1 - eased));
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _ctrl,
                        builder: (context, _) => _Intro(
                          headline: _stagger(0.0, reduceMotion: reduceMotion),
                          body: _stagger(0.12, reduceMotion: reduceMotion),
                          demo: _stagger(0.24, reduceMotion: reduceMotion),
                          trust: _stagger(0.36, reduceMotion: reduceMotion),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space16,
                V2Spacing.space24,
                V2Spacing.space24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PGPillButton(
                    label: 'Start scanning',
                    icon: Icons.qr_code_scanner_rounded,
                    expand: true,
                    onPressed: () => _finish(Routes.scan),
                  ),
                  const SizedBox(height: V2Spacing.space8),
                  TextButton(
                    onPressed: () => _finish(Routes.profileWizard),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      foregroundColor: context.v2.accent,
                    ),
                    child: Text(
                      'Set up my profile first',
                      style: V2Typography.label(color: context.v2.accent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  final ({double opacity, double lift}) headline;
  final ({double opacity, double lift}) body;
  final ({double opacity, double lift}) demo;
  final ({double opacity, double lift}) trust;

  const _Intro({
    required this.headline,
    required this.body,
    required this.demo,
    required this.trust,
  });

  Widget _faded(({double opacity, double lift}) s, Widget child) => Opacity(
    opacity: s.opacity,
    child: Transform.translate(offset: Offset(0, s.lift), child: child),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V2Spacing.space24,
        V2Spacing.space32,
        V2Spacing.space24,
        V2Spacing.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _faded(
            headline,
            Text(
              'Scan a supplement.\nSee the answer.',
              style: V2Typography.displayXs(color: context.v2.fg),
            ),
          ),
          const SizedBox(height: V2Spacing.space16),
          _faded(
            body,
            Text(
              'The PG Score, key risks and the sources behind them.',
              style: V2Typography.bodyXl(color: context.v2.fgMuted),
            ),
          ),
          const SizedBox(height: V2Spacing.space32),
          _faded(demo, const _MiniProductPreview()),
          const SizedBox(height: V2Spacing.space32),
          _faded(trust, const _TrustRows()),
        ],
      ),
    );
  }
}

/// Mini product result card — built from real v2 components (eats our
/// own dog food).
class _MiniProductPreview extends StatelessWidget {
  const _MiniProductPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: context.v2.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: context.v2.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // An illustration, not a catalog result: a real brand here wore a
          // score its catalog product doesn't have.
          const PGEyebrow('Example'),
          const SizedBox(height: V2Spacing.space4),
          Text(
            'Magnesium Glycinate',
            style: V2Typography.titleSm(color: context.v2.fg),
          ),
          const SizedBox(height: V2Spacing.space12),
          // Mirrors production ScoreLine: dot + score + tier label.
          const _ScoreLineDemo(score: 86),
        ],
      ),
    );
  }
}

/// Mini ScoreLine for the onboarding preview: tier color dot +
/// `86/100` + tier label, sized down to fit a preview card.
class _ScoreLineDemo extends StatelessWidget {
  final int score;
  const _ScoreLineDemo({required this.score});

  @override
  Widget build(BuildContext context) {
    final tier = legacyTierForScore(score);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: tier.color(Theme.of(context).brightness),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: V2Spacing.space8),
        Text(
          '$score/100',
          style: V2Typography.bodyMedium(color: context.v2.fg),
        ),
        const SizedBox(width: V2Spacing.space8),
        Text(
          tier.label,
          style: V2Typography.bodyMedium(
            color: tier.textColor(Theme.of(context).brightness),
          ),
        ),
      ],
    );
  }
}

/// Where the answers come from and where your data lives — stated, not
/// promised. (The old "Every check ties back to published NIH ODS, PubMed,
/// and FDA guidance" overclaimed a finite curated rule set.)
class _TrustRows extends StatelessWidget {
  const _TrustRows();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _TrustRow(eyebrow: 'Sources', label: 'NIH ODS · PubMed · FDA'),
        SizedBox(height: V2Spacing.space16),
        _TrustRow(
          eyebrow: 'Privacy',
          label:
              'Your profile, medications and allergies are saved on this '
              'device only',
        ),
      ],
    );
  }
}

class _TrustRow extends StatelessWidget {
  final String eyebrow;
  final String label;

  const _TrustRow({required this.eyebrow, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: PGEyebrow(eyebrow, color: context.v2.fgMuted),
        ),
        const SizedBox(width: V2Spacing.space12),
        Expanded(
          child: Text(label, style: V2Typography.body(color: context.v2.fg)),
        ),
      ],
    );
  }
}
