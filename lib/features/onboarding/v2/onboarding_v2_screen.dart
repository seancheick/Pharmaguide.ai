import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/components/pg_celebration.dart';
import 'package:pharmaguide/core/components/pg_eyebrow.dart';
import 'package:pharmaguide/core/components/pg_goal_chip.dart';
import 'package:pharmaguide/core/components/pg_halo_background.dart';
import 'package:pharmaguide/core/components/pg_pill_button.dart';
import 'package:pharmaguide/core/components/pg_progress_dots.dart';
import 'package:pharmaguide/core/scoring/score_tier.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/v2/v2_colors.dart';
import 'package:pharmaguide/core/theme/v2/v2_motion.dart';
import 'package:pharmaguide/core/theme/v2/v2_shadows.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';

/// v2 onboarding — editorial 4-step intro.
///
/// Preserves the legacy flow's information architecture (Value → Profile
/// → Goals → Trust) — it's well-considered — but redesigns every visual
/// element to v2:
/// - Newsreader serif emotional headline (one line per step)
/// - Mono caps eyebrow showing progress ("STEP 02 / 04")
/// - Geist Sans body copy, 400/500 weights only
/// - Step-specific demo cards built from v2 components
/// - Pill primary CTA + ghost skip
/// - `PGProgressDots` between dots/CTA row
/// - 80ms stagger entrance per element on each step change
/// - `PGCelebration` before navigating home from final step
///
/// When [autoFinish] is false (used by the dev gallery preview), the
/// finish handler is suppressed so the screen can be inspected without
/// modifying onboarding prefs or navigating.
class OnboardingV2Screen extends ConsumerStatefulWidget {
  final bool autoFinish;

  const OnboardingV2Screen({super.key, this.autoFinish = true});

  @override
  ConsumerState<OnboardingV2Screen> createState() => _OnboardingV2ScreenState();
}

class _OnboardingV2ScreenState extends ConsumerState<OnboardingV2Screen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _celebrating = false;
  final _selectedGoals = <String>{};

  // 8 most common, friendly goal labels — same set as legacy onboarding
  // so analytics + downstream provider logic keep working.
  static const _goals = <String, String>{
    'GOAL_INCREASE_ENERGY': 'Energy',
    'GOAL_SLEEP_QUALITY': 'Sleep',
    'GOAL_CARDIOVASCULAR_HEART_HEALTH': 'Heart health',
    'GOAL_DIGESTIVE_HEALTH': 'Gut health',
    'GOAL_MUSCLE_GROWTH_RECOVERY': 'Fitness',
    'GOAL_PRENATAL_PREGNANCY': 'Pregnancy / TTC',
    'GOAL_IMMUNE_SUPPORT': 'Immune support',
    'GOAL_WEIGHT_MANAGEMENT': 'Weight management',
  };

  static const _totalPages = 4;

  void _next() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: V2Motion.base,
        curve: V2Motion.smooth,
      );
    } else {
      _startFinish();
    }
  }

  void _startFinish() {
    if (!widget.autoFinish) {
      // Dev gallery mode — preview the celebration without navigating.
      setState(() => _celebrating = true);
      return;
    }
    setState(() => _celebrating = true);
  }

  Future<void> _celebrationComplete({bool toProfileSetup = false}) async {
    if (!widget.autoFinish) {
      // Reset for repeated preview viewing in the gallery. setState
      // schedules the PageView to be rebuilt; the controller is only
      // attached after the next frame, so defer jumpToPage to a
      // post-frame callback to avoid the
      // "PageController is not attached to a PageView" assertion that
      // fires when jumpToPage runs while _celebrating is still true.
      if (!mounted) return;
      setState(() {
        _celebrating = false;
        _currentPage = 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
      return;
    }
    if (_selectedGoals.isNotEmpty) {
      ref.read(profileProvider.notifier).setGoals(_selectedGoals.toList());
    }
    await OnboardingPrefs.markSeen();
    if (!mounted) return;
    GoRouter.of(context).go(toProfileSetup ? Routes.profileSetup : Routes.home);
  }

  Future<void> _skip() async {
    if (!widget.autoFinish) return;
    await OnboardingPrefs.markSeen();
    if (!mounted) return;
    GoRouter.of(context).go(Routes.home);
  }

  void _toggleGoal(String id) {
    setState(() {
      if (_selectedGoals.contains(id)) {
        _selectedGoals.remove(id);
      } else if (_selectedGoals.length < 2) {
        _selectedGoals.add(id);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_celebrating) {
      return Scaffold(
        backgroundColor: V2Colors.bg,
        body: PGHaloBackground(
          origin: const Alignment(0, -0.2),
          radius: 1.1,
          intensity: 0.08,
          child: Center(
            child: PGCelebration(
              eyebrow: "You're set",
              headline: 'Let’s start scanning.',
              subline:
                  _selectedGoals.isEmpty
                      ? 'We’ll personalize as you go.'
                      : 'We’ll prioritize what matters to you.',
              onComplete: () => _celebrationComplete(),
            ),
          ),
        ),
      );
    }

    final isLast = _currentPage == _totalPages - 1;

    return Scaffold(
      backgroundColor: V2Colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Skip + step indicator row.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space12,
                V2Spacing.space24,
                0,
              ),
              child: Row(
                children: [
                  PGEyebrow(
                    'Step ${(_currentPage + 1).toString().padLeft(2, '0')}'
                    ' / ${_totalPages.toString().padLeft(2, '0')}',
                  ),
                  const Spacer(),
                  if (!isLast)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _skip,
                      child: Text(
                        'Skip',
                        style: V2Typography.label(color: V2Colors.fgMuted),
                      ),
                    ),
                ],
              ),
            ),
            // Pages.
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  const _ValuePage(),
                  const _ProfilePage(),
                  _GoalsPage(
                    goals: _goals,
                    selected: _selectedGoals,
                    onToggle: _toggleGoal,
                  ),
                  _TrustPage(
                    onSetupProfile: () {
                      setState(() => _celebrating = true);
                    },
                    onSetupProfileCelebrationDone: () =>
                        _celebrationComplete(toProfileSetup: true),
                  ),
                ],
              ),
            ),
            // Dots + primary CTA.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V2Spacing.space24,
                V2Spacing.space16,
                V2Spacing.space24,
                V2Spacing.space48,
              ),
              child: Row(
                children: [
                  PGProgressDots(total: _totalPages, current: _currentPage),
                  const Spacer(),
                  PGPillButton(
                    label: isLast ? 'Start scanning' : 'Continue',
                    icon: isLast
                        ? Icons.qr_code_scanner_rounded
                        : Icons.arrow_forward_rounded,
                    onPressed: _next,
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

// =============================================================================
// Shared step shell
// =============================================================================

class _StepShell extends StatefulWidget {
  final String headline;
  final String body;
  final Widget? demo;

  /// Optional footer rendered below the body — useful for tertiary text
  /// or extra CTAs (e.g. trust page's "Set up safety profile" link).
  final Widget? footer;

  const _StepShell({
    required this.headline,
    required this.body,
    this.demo,
    this.footer,
  });

  @override
  State<_StepShell> createState() => _StepShellState();
}

class _StepShellState extends State<_StepShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: V2Motion.slower,
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Compute opacity + lift for an 80ms-stagger element starting at
  /// [delayFraction] of the controller's total duration.
  ({double opacity, double lift}) _stagger(double delayFraction) {
    final t = ((_ctrl.value - delayFraction) / 0.6).clamp(0.0, 1.0);
    final eased = V2Motion.decelerate.transform(t);
    return (opacity: eased, lift: 14 * (1 - eased));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final headline = _stagger(0.0);
        final body = _stagger(0.12);
        final demo = _stagger(0.24);
        final footer = _stagger(0.36);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: V2Spacing.space24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: headline.opacity,
                child: Transform.translate(
                  offset: Offset(0, headline.lift),
                  child: Text(
                    widget.headline,
                    style: V2Typography.displayXs(color: V2Colors.fg),
                  ),
                ),
              ),
              const SizedBox(height: V2Spacing.space16),
              Opacity(
                opacity: body.opacity,
                child: Transform.translate(
                  offset: Offset(0, body.lift),
                  child: Text(
                    widget.body,
                    style: V2Typography.bodyXl(color: V2Colors.fgMuted),
                  ),
                ),
              ),
              if (widget.demo != null) ...[
                const SizedBox(height: V2Spacing.space32),
                Opacity(
                  opacity: demo.opacity,
                  child: Transform.translate(
                    offset: Offset(0, demo.lift),
                    child: widget.demo,
                  ),
                ),
              ],
              if (widget.footer != null) ...[
                const SizedBox(height: V2Spacing.space24),
                Opacity(
                  opacity: footer.opacity,
                  child: Transform.translate(
                    offset: Offset(0, footer.lift),
                    child: widget.footer,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// Page 1 — Value preview ("Scan → answer")
// =============================================================================

class _ValuePage extends StatelessWidget {
  const _ValuePage();

  @override
  Widget build(BuildContext context) {
    return const _StepShell(
      headline: 'Scan a supplement.\nSee the answer.',
      body: 'PG Score, key risks, and references — instantly.',
      demo: _MiniProductPreview(),
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
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PGEyebrow('Thorne'),
          const SizedBox(height: V2Spacing.space4),
          Text(
            'Magnesium Glycinate',
            style: V2Typography.titleSm(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space12),
          // Mirrors production ScoreLine: dot + score + tier label.
          const _ScoreLineDemo(score: 86),
        ],
      ),
    );
  }
}

/// Mini ScoreLine for the onboarding preview. Mirrors the production
/// `lib/features/product_detail/widgets/score_line.dart` pattern: tier
/// color dot + `86/100` + tier label, sized down to fit a preview card.
class _ScoreLineDemo extends StatelessWidget {
  final int score;
  const _ScoreLineDemo({required this.score});

  @override
  Widget build(BuildContext context) {
    final tier = tierForScore(score);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: tier.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: V2Spacing.space8),
        Text(
          '$score/100',
          style: V2Typography.bodyMedium(color: V2Colors.fg),
        ),
        const SizedBox(width: V2Spacing.space8),
        Text(tier.label, style: V2Typography.bodyMedium(color: tier.color)),
      ],
    );
  }
}

// =============================================================================
// Page 2 — Profile preview ("Built around you")
// =============================================================================

class _ProfilePage extends StatelessWidget {
  const _ProfilePage();

  @override
  Widget build(BuildContext context) {
    return const _StepShell(
      headline: 'Built around\nyour stack.',
      body:
          'Add conditions or medications. We check every supplement against you.',
      demo: _AppliesToYouPreview(),
    );
  }
}

class _AppliesToYouPreview extends StatelessWidget {
  const _AppliesToYouPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(V2Spacing.space16),
      decoration: BoxDecoration(
        color: V2Colors.surface,
        borderRadius: BorderRadius.circular(V2Spacing.radiusCard),
        border: Border.all(color: V2Colors.outline),
        boxShadow: V2Shadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PGEyebrow('Applies to you', color: V2Colors.caution),
          const SizedBox(height: V2Spacing.space12),
          Text(
            'May affect your blood-thinner medication.',
            style: V2Typography.bodyXl(color: V2Colors.fg),
          ),
          const SizedBox(height: V2Spacing.space8),
          Text(
            'Moderate evidence · worth a check',
            style: V2Typography.caption(color: V2Colors.caution),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Page 3 — Goals ("What matters")
// =============================================================================

class _GoalsPage extends StatelessWidget {
  final Map<String, String> goals;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _GoalsPage({
    required this.goals,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final atMax = selected.length >= 2;
    return _StepShell(
      headline: 'What matters\nmost to you?',
      body:
          'Pick up to 2. We use these to explain what matters after every scan.',
      demo: Wrap(
        spacing: V2Spacing.space8,
        runSpacing: V2Spacing.space8,
        children: goals.entries.map((e) {
          final isSelected = selected.contains(e.key);
          return PGGoalChip(
            label: e.value,
            selected: isSelected,
            disabled: atMax && !isSelected,
            onTap: () => onToggle(e.key),
          );
        }).toList(),
      ),
      footer: selected.isEmpty
          ? Text(
              'You can skip this — we’ll learn as you go.',
              style: V2Typography.caption(color: V2Colors.fgMuted),
            )
          : null,
    );
  }
}

// =============================================================================
// Page 4 — Trust ("Clinical, not commercial")
// =============================================================================

class _TrustPage extends StatelessWidget {
  /// Called when the user taps the "Set up safety profile" link. Parent
  /// triggers a celebration, then routes to profile setup once done.
  final VoidCallback onSetupProfile;
  final VoidCallback onSetupProfileCelebrationDone;

  const _TrustPage({
    required this.onSetupProfile,
    required this.onSetupProfileCelebrationDone,
  });

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      headline: 'Clinical,\nnot commercial.',
      body:
          'Every check ties back to published NIH ODS, PubMed, and FDA guidance.',
      demo: const _TrustBullets(),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your profile stays on this device.',
            style: V2Typography.caption(color: V2Colors.fgMuted),
          ),
          const SizedBox(height: V2Spacing.space12),
          PGPillButton(
            label: 'Set up safety profile',
            variant: PGPillVariant.ghost,
            onPressed: onSetupProfile,
          ),
        ],
      ),
    );
  }
}

class _TrustBullets extends StatelessWidget {
  const _TrustBullets();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _TrustRow(
          eyebrow: 'Sources',
          label: 'NIH ODS · PubMed · FDA',
        ),
        SizedBox(height: V2Spacing.space16),
        _TrustRow(
          eyebrow: 'Tone',
          label: 'Plain-language warnings, no hype',
        ),
        SizedBox(height: V2Spacing.space16),
        _TrustRow(
          eyebrow: 'Privacy',
          label: 'Health data never leaves your device',
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
          child: PGEyebrow(eyebrow, color: V2Colors.fgMuted),
        ),
        const SizedBox(width: V2Spacing.space12),
        Expanded(
          child: Text(
            label,
            style: V2Typography.body(color: V2Colors.fg),
          ),
        ),
      ],
    );
  }
}
