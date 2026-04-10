import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/features/home/home_screen.dart';
import 'package:pharmaguide/features/onboarding/onboarding_screen.dart';
import 'package:pharmaguide/features/profile/profile_setup_screen.dart';
import 'package:pharmaguide/features/scanner/scanner_screen.dart';
import 'package:pharmaguide/features/search/search_screen.dart';
import 'package:pharmaguide/features/product_detail/product_detail_screen.dart';
import 'package:pharmaguide/features/settings/settings_screen.dart';
import 'package:pharmaguide/features/stack/stack_screen.dart';

// Placeholder screens — will be replaced by real implementations
class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
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

  const CatalogUnavailableScreen({
    super.key,
    this.message,
    this.onRetry,
  });

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

GoRouter _buildRouter({
  required bool catalogAvailable,
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
    initialLocation: Routes.home,
    routes: [
      ShellRoute(
        builder: (context, state, child) => _AppShell(child: child),
        routes: [
          GoRoute(
              path: Routes.home,
              builder: (_, __) => catalogRoute(const HomeScreen())),
          GoRoute(
              path: Routes.scan,
              builder: (_, __) => catalogRoute(const ScanScreen())),
          GoRoute(
              path: Routes.stack,
              builder: (_, __) => catalogRoute(const StackScreen())),
          GoRoute(path: Routes.chat, builder: (_, __) => const ChatScreen()),
          GoRoute(path: Routes.profile, builder: (_, __) => const SettingsScreen()),
        ],
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.profileSetup,
        builder: (_, __) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: Routes.search,
        builder: (_, state) => catalogRoute(
          SearchScreen(initialCategory: state.uri.queryParameters['category']),
        ),
      ),
      GoRoute(
        path: '${Routes.product}/:dsldId',
        builder: (context, state) {
          final dsldId = state.pathParameters['dsldId'] ?? '';
          return catalogRoute(ProductDetailScreen(dsldId: dsldId));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(context),
        onDestinationSelected: (index) {
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
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.layers_outlined),
            selectedIcon: Icon(Icons.layers),
            label: 'Stack',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
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

  const PharmaGuideApp({
    super.key,
    this.catalogAvailable = true,
    this.catalogUnavailableReason,
    this.onRetryCatalogLoad,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PharmaGuide',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _buildRouter(
        catalogAvailable: catalogAvailable,
        catalogUnavailableReason: catalogUnavailableReason,
        onRetryCatalogLoad: onRetryCatalogLoad,
      ),
    );
  }
}
