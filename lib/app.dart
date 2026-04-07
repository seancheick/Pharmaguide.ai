import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/app_colors.dart';
import 'package:pharmaguide/features/onboarding/onboarding_screen.dart';
import 'package:pharmaguide/features/profile/profile_setup_screen.dart';

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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _PlaceholderScreen(title: 'Home');
}

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _PlaceholderScreen(title: 'Scan');
}

class StackScreen extends StatelessWidget {
  const StackScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _PlaceholderScreen(title: 'My Stack');
}

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _PlaceholderScreen(title: 'AI Pharmacist');
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _PlaceholderScreen(title: 'Profile');
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => _AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
        GoRoute(path: '/stack', builder: (_, __) => const StackScreen()),
        GoRoute(path: '/chat', builder: (_, __) => const ChatScreen()),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      ],
    ),
    // Routes outside the shell (no bottom nav)
    GoRoute(
      path: '/onboarding',
      builder: (_, __) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/profile/setup',
      builder: (_, __) => const ProfileSetupScreen(),
    ),
    GoRoute(
      path: '/product/:dsldId',
      builder: (context, state) {
        final dsldId = state.pathParameters['dsldId'] ?? '';
        return _PlaceholderScreen(title: 'Product $dsldId');
      },
    ),
  ],
);

class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/scan')) return 1;
    if (location.startsWith('/stack')) return 2;
    if (location.startsWith('/chat')) return 3;
    if (location.startsWith('/profile')) return 4;
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
              context.go('/');
            case 1:
              context.go('/scan');
            case 2:
              context.go('/stack');
            case 3:
              context.go('/chat');
            case 4:
              context.go('/profile');
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
  const PharmaGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PharmaGuide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A7D6F),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Inter',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A7D6F),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Inter',
      ),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
