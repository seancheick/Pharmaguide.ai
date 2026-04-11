import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_motion.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';

/// 3-slide onboarding intro — first thing users see on a fresh install.
///
/// Premium design language: soft-tinted icon wells, tight letter-spacing
/// on the display title, smooth animated page indicator. Pulls styling
/// exclusively from [Theme.of] + [AppTheme] tokens so it adapts to
/// light/dark mode and respects Dynamic Type.
///
/// Persists `hasSeenOnboarding = true` via [OnboardingPrefs] before
/// navigating away so the app never shows this screen twice.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPageData(
      title: 'Know what you take',
      description:
          'Scan any supplement barcode for an instant clinical-grade safety '
          'score backed by real research.',
      icon: Icons.qr_code_scanner_rounded,
    ),
    _OnboardingPageData(
      title: 'Personalized safety',
      description:
          'Add your health conditions and medications. Get warnings tailored '
          'to your unique profile.',
      icon: Icons.shield_outlined,
    ),
    _OnboardingPageData(
      title: 'Your data stays private',
      description:
          'All health information is encrypted on your device. We never '
          'upload your personal data.',
      icon: Icons.lock_outline_rounded,
    ),
  ];

  Future<void> _next() async {
    if (_currentPage < _pages.length - 1) {
      await _controller.nextPage(
        duration: AppMotion.medium,
        curve: AppMotion.standard,
      );
    } else {
      await _complete();
    }
  }

  Future<void> _complete() async {
    await OnboardingPrefs.markSeen();
    if (!mounted) return;
    GoRouter.of(context).go(Routes.profileSetup);
  }

  Future<void> _skip() async {
    await OnboardingPrefs.markSeen();
    if (!mounted) return;
    GoRouter.of(context).go(Routes.home);
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
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button — top-right, tertiary text style
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
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) =>
                    setState(() => _currentPage = index),
                itemBuilder: (context, index) => _OnboardingPage(
                  data: _pages[index],
                ),
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
                  // Animated page dots — active dot elongates
                  Row(
                    children: List.generate(_pages.length, (index) {
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
                  // Next / Get Started
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.space32,
                      ),
                      minimumSize: const Size(0, 52),
                    ),
                    child: Text(isLast ? 'Get started' : 'Next'),
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

class _OnboardingPageData {
  final String title;
  final String description;
  final IconData icon;

  const _OnboardingPageData({
    required this.title,
    required this.description,
    required this.icon,
  });
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;

  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Soft-tinted icon well — the premium alternative to a naked icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.22),
                width: 1.2,
              ),
            ),
            child: Icon(
              data.icon,
              size: 52,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: AppTheme.space40),
          Text(
            data.title,
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.space16),
          Text(
            data.description,
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
