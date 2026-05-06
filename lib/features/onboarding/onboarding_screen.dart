import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/features/profile/profile_provider.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';

/// 4-step premium onboarding — activation-first, not claim-first.
///
/// 1. Value preview — realistic mini product card showing what the app does
/// 2. Profile value preview — shows "Applies to you" personalization
/// 3. Tiny personalization — quick goal chips (max 2), persisted to profile
/// 4. Trust + CTA — clinical references, no hype, start scanning
///
/// Does NOT force full profile setup before first scan. Goals collected
/// during onboarding feed the Fit layer immediately. Detailed conditions,
/// medications, and allergens are deferred until the user sees value or
/// taps "Set up safety profile."
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;
  final _selectedGoals = <String>{};

  // Curated subset of goals for onboarding — 8 most common, user-friendly labels.
  static const _onboardingGoals = <String, String>{
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

  Future<void> _next() async {
    if (_currentPage < _totalPages - 1) {
      await _controller.nextPage(
        duration: AppMotion.medium,
        curve: AppMotion.standard,
      );
    } else {
      await _finish();
    }
  }

  Future<void> _finish() async {
    // Persist selected goals if any
    if (_selectedGoals.isNotEmpty) {
      ref.read(profileProvider.notifier).setGoals(
            _selectedGoals.toList(),
          );
    }
    await OnboardingPrefs.markSeen();
    if (!mounted) return;
    GoRouter.of(context).go(Routes.home);
  }

  Future<void> _finishWithProfileSetup() async {
    if (_selectedGoals.isNotEmpty) {
      ref.read(profileProvider.notifier).setGoals(
            _selectedGoals.toList(),
          );
    }
    await OnboardingPrefs.markSeen();
    if (!mounted) return;
    GoRouter.of(context).go(Routes.profileSetup);
  }

  Future<void> _skip() async {
    await OnboardingPrefs.markSeen();
    if (!mounted) return;
    GoRouter.of(context).go(Routes.home);
  }

  void _toggleGoal(String goalId) {
    setState(() {
      if (_selectedGoals.contains(goalId)) {
        _selectedGoals.remove(goalId);
      } else if (_selectedGoals.length < 2) {
        _selectedGoals.add(goalId);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLast = _currentPage == _totalPages - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space20,
                  AppTheme.space12,
                  AppTheme.space20,
                  0,
                ),
                child: TextButton(
                  onPressed: _skip,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  child: const Text('Skip'),
                ),
              ),
            ),
            // Pages
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: [
                  _ValuePreviewPage(),
                  _ProfileValuePage(),
                  _GoalSelectionPage(
                    selectedGoals: _selectedGoals,
                    onToggle: _toggleGoal,
                  ),
                  _TrustPage(
                    onSetupProfile: _finishWithProfileSetup,
                  ),
                ],
              ),
            ),
            // Dots + primary button
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space24,
                AppTheme.space16,
                AppTheme.space24,
                AppTheme.space48,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(_totalPages, (index) {
                      final selected = index == _currentPage;
                      return AnimatedContainer(
                        duration: AppMotion.medium,
                        curve: AppMotion.standard,
                        margin: const EdgeInsets.only(right: 8),
                        width: selected ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: selected
                              ? scheme.primary
                              : scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.space32,
                      ),
                      minimumSize: const Size(0, 52),
                    ),
                    child: Text(isLast ? 'Start scanning' : 'Continue'),
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

// ---------------------------------------------------------------------------
// Page 1: Value preview — realistic mini product card
// ---------------------------------------------------------------------------

class _ValuePreviewPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mini product result card
          Container(
            padding: const EdgeInsets.all(AppTheme.space16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.severitySafe.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                      child: Center(
                        child: Text(
                          '86',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.severitySafe,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTheme.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Magnesium Glycinate',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'PG Score 86 \u00b7 Excellent',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.severitySafe,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.space12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space8,
                    vertical: AppTheme.space4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Text(
                    'Review before use: 1 note',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.space40),
          Text(
            'Scan a supplement.\nUnderstand the risk.',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.space16),
          Text(
            'See quality, label confidence, and safety notes in seconds.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 2: Profile value preview — "Applies to you" card
// ---------------------------------------------------------------------------

class _ProfileValuePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mini "Applies to you" card
          Container(
            padding: const EdgeInsets.all(AppTheme.space16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              border: Border.all(
                color: AppTheme.severityCaution.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: AppTheme.severityCaution,
                    ),
                    const SizedBox(width: AppTheme.space8),
                    Text(
                      'Applies to you',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.severityCaution,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.space12),
                Text(
                  'May affect blood-thinner medication',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTheme.space4),
                Text(
                  'Evidence: Moderate',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.space40),
          Text(
            'Checks built around you.',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.space16),
          Text(
            'Add age, goals, conditions, or medications to see what '
            'actually applies to your profile.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 3: Tiny personalization — goal chips
// ---------------------------------------------------------------------------

class _GoalSelectionPage extends StatelessWidget {
  final Set<String> selectedGoals;
  final ValueChanged<String> onToggle;

  const _GoalSelectionPage({
    required this.selectedGoals,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'What are you checking\nsupplements for?',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            'Pick up to 2. We use this to explain what matters most after each scan.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.space24),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            alignment: WrapAlignment.center,
            children: _OnboardingScreenState._onboardingGoals.entries.map((e) {
              final selected = selectedGoals.contains(e.key);
              final atMax = selectedGoals.length >= 2 && !selected;
              return FilterChip(
                label: Text(e.value),
                selected: selected,
                onSelected: atMax ? null : (_) => onToggle(e.key),
                selectedColor: scheme.primary.withValues(alpha: 0.14),
                checkmarkColor: scheme.primary,
                side: BorderSide(
                  color: selected
                      ? scheme.primary
                      : scheme.outlineVariant,
                ),
                labelStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppTheme.space16),
          if (selectedGoals.isEmpty)
            Text(
              'You can also skip this.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 4: Trust + CTA
// ---------------------------------------------------------------------------

class _TrustPage extends StatelessWidget {
  final VoidCallback onSetupProfile;

  const _TrustPage({required this.onSetupProfile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Trust card visual
          Container(
            padding: const EdgeInsets.all(AppTheme.space16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: AppTheme.space8),
                    Text(
                      'References',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.space8),
                Text(
                  'NIH ODS \u00b7 PubMed \u00b7 FDA',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppTheme.space4),
                Text(
                  'Clinician-reviewed guidance',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.space40),
          Text(
            'Built for clinical clarity.',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.space20),
          const _TrustBullet(
            icon: Icons.menu_book_rounded,
            text: 'Published clinical references',
          ),
          const SizedBox(height: AppTheme.space12),
          const _TrustBullet(
            icon: Icons.warning_amber_rounded,
            text: 'Plain-language warnings',
          ),
          const SizedBox(height: AppTheme.space12),
          const _TrustBullet(
            icon: Icons.do_not_disturb_alt_rounded,
            text: 'No supplement hype',
          ),
          const SizedBox(height: AppTheme.space24),
          Text(
            'Your profile stays under your control.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.space16),
          TextButton(
            onPressed: onSetupProfile,
            child: const Text('Set up safety profile'),
          ),
        ],
      ),
    );
  }
}

class _TrustBullet extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TrustBullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: AppTheme.space8),
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
