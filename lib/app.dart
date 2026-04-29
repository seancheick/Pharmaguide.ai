import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/core/widgets/pg_frosted_nav_bar.dart';
import 'package:pharmaguide/features/home/home_screen.dart';
import 'package:pharmaguide/features/onboarding/onboarding_screen.dart';
import 'package:pharmaguide/features/profile/profile_setup_screen.dart';
import 'package:pharmaguide/features/scanner/scanner_screen.dart';
import 'package:pharmaguide/features/search/search_screen.dart';
import 'package:pharmaguide/features/product_detail/product_detail_screen.dart';
import 'package:pharmaguide/features/quick_check/quick_check_screen.dart';
import 'package:pharmaguide/features/settings/settings_screen.dart';
import 'package:pharmaguide/features/splash/animated_splash_screen.dart';
import 'package:pharmaguide/features/stack/stack_screen.dart';

/// App-wide [ScaffoldMessenger] key. `main.dart` uses this to show the
/// "catalog updated" snackbar from outside the widget tree when the OTA
/// in-session swap completes (T0.6). Defining it here keeps the
/// `MaterialApp.router(scaffoldMessengerKey: …)` wiring colocated with
/// the messenger consumers.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// Placeholder screens — will be replaced by real implementations
class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});
  @override
  Widget build(BuildContext context) => const ScannerScreen();
}

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _PlaceholderScreen(title: 'AI Pharmacist');
}

class CatalogUnavailableScreen extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const CatalogUnavailableScreen({super.key, this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catalog Unavailable')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                message ??
                    'The verified supplement catalog is not available on this device yet.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(Routes.profile),
                child: const Text('Open Profile'),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('Retry Catalog Download'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Returns a [Page] that maps to the platform's idiomatic page transition:
/// [CupertinoPage] on iOS (slide-from-right + edge-swipe-back gesture)
/// and [MaterialPage] elsewhere (Android slide-up / fade). Used by
/// sub-page routes so iOS users get the swipe-back-from-edge gesture
/// they expect from every other native iOS app.
Page<dynamic> _platformPage(GoRouterState state, Widget child) {
  return Platform.isIOS
      ? CupertinoPage<void>(key: state.pageKey, child: child)
      : MaterialPage<void>(key: state.pageKey, child: child);
}

GoRouter _buildRouter({
  required bool catalogAvailable,
  required bool hasSeenOnboarding,
  String? catalogUnavailableReason,
  VoidCallback? onRetryCatalogLoad,
}) {
  Widget catalogRoute(Widget child) {
    if (catalogAvailable) return child;
    return CatalogUnavailableScreen(
      message: catalogUnavailableReason,
      onRetry: onRetryCatalogLoad,
    );
  }

  return GoRouter(
    // Fresh installs start at onboarding; returning users go straight to
    // home. `OnboardingPrefs.markSeen()` is called in the onboarding
    // screen's Next/Skip handlers so this only fires once per device.
    initialLocation:
        '${Routes.splashIntro}?next='
        '${Uri.encodeComponent(hasSeenOnboarding ? Routes.home : Routes.onboarding)}',
    routes: [
      ShellRoute(
        builder: (context, state, child) => _AppShell(child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (_, __) => catalogRoute(const HomeScreen()),
          ),
          GoRoute(
            path: Routes.scan,
            builder: (_, __) => catalogRoute(const ScanScreen()),
          ),
          GoRoute(
            path: Routes.stack,
            builder: (_, __) => catalogRoute(const StackScreen()),
          ),
          GoRoute(path: Routes.chat, builder: (_, __) => const ChatScreen()),
          GoRoute(
            path: Routes.profile,
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),
      // Sub-pages live outside the shell — they have their own app bar with
      // back button and (for product detail) a sticky action bar. Nesting
      // them inside the shell causes double-Scaffold conflicts.
      //
      // Use pageBuilder + _platformPage for routes that should support
      // iOS swipe-back-from-edge (Apple HIG default for stack navigation).
      // Onboarding intentionally stays Material — it's a linear flow and
      // swipe-back would let users escape it before completing.
      GoRoute(
        path: Routes.splashIntro,
        builder: (_, state) {
          final next = state.uri.queryParameters['next'] ?? Routes.home;
          return AnimatedSplashScreen(nextRoute: next);
        },
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.profileSetup,
        pageBuilder: (_, state) =>
            _platformPage(state, const ProfileSetupScreen()),
      ),
      GoRoute(
        path: Routes.search,
        pageBuilder: (_, state) => _platformPage(
          state,
          catalogRoute(
            SearchScreen(
              initialCategory: state.uri.queryParameters['category'],
              initialQuery: state.uri.queryParameters['query'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: Routes.quickCheck,
        pageBuilder: (_, state) =>
            _platformPage(state, catalogRoute(const QuickCheckScreen())),
      ),
      GoRoute(
        path: '${Routes.product}/:dsldId',
        pageBuilder: (context, state) {
          final dsldId = state.pathParameters['dsldId'] ?? '';
          return _platformPage(
            state,
            catalogRoute(ProductDetailScreen(dsldId: dsldId)),
          );
        },
      ),
    ],
  );
}

class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith(Routes.scan)) return 1;
    if (location.startsWith(Routes.stack)) return 2;
    if (location.startsWith(Routes.chat)) return 3;
    if (location.startsWith(Routes.profile)) return 4;
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(Routes.home);
      case 1:
        context.go(Routes.scan);
      case 2:
        context.go(Routes.stack);
      case 3:
        context.go(Routes.chat);
      case 4:
        context.go(Routes.profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // `extendBody: true` lets scrollable content flow *under* the frosted
      // nav bar so the BackdropFilter has pixels to blur — this is what
      // makes the Apple-style glass effect actually visible. Each modal
      // bottom sheet is responsible for adding bottom padding equal to
      // [kPGNavBarHeight] so its content doesn't sit behind the nav bar.
      extendBody: true,
      body: child,
      bottomNavigationBar: PGFrostedNavBar(
        selectedIndex: _selectedIndex(context),
        onDestinationSelected: (i) => _onDestinationSelected(context, i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner_rounded),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.layers_outlined),
            selectedIcon: Icon(Icons.layers_rounded),
            label: 'Stack',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class PharmaGuideApp extends StatelessWidget {
  final bool catalogAvailable;
  final String? catalogUnavailableReason;
  final VoidCallback? onRetryCatalogLoad;
  final bool hasSeenOnboarding;

  const PharmaGuideApp({
    super.key,
    this.catalogAvailable = true,
    this.catalogUnavailableReason,
    this.onRetryCatalogLoad,
    this.hasSeenOnboarding = true,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PharmaGuide',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _buildRouter(
        catalogAvailable: catalogAvailable,
        hasSeenOnboarding: hasSeenOnboarding,
        catalogUnavailableReason: catalogUnavailableReason,
        onRetryCatalogLoad: onRetryCatalogLoad,
      ),
      // Global Dynamic Type clamp.
      //
      // Accessibility text-scale settings on iOS go up to AX5 (≈3.1x) and
      // on Android up to ≈2.0x. Letting the app scale unconstrained
      // breaks card layouts (overflowing icons, ellipsized titles,
      // truncated counts). Cap to a 0.9–1.4x band globally — large
      // enough to meaningfully help low-vision users, small enough to
      // keep editorial layouts readable. Long body content surfaces that
      // already handle large text (e.g. product detail) can opt back into
      // full Dynamic Type with a local MediaQuery override.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clamped = mq.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.4,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: clamped),
          child: child!,
        );
      },
    );
  }
}
