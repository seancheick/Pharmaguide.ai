import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/features/splash/animated_splash_screen.dart';

void main() {
  group('AnimatedSplashScreen', () {
    testWidgets('renders the logo and brand-teal background', (tester) async {
      // Mount with a router so GoRouter.of(context).go works.
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const AnimatedSplashScreen(nextRoute: '/done'),
          ),
          GoRoute(
            path: '/done',
            builder: (_, __) => const Scaffold(body: Text('done-marker')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      // Background is a brand-teal gradient via DecoratedBox.
      expect(find.byType(DecoratedBox), findsWidgets);
    });

    testWidgets('navigates to nextRoute after animation completes', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const AnimatedSplashScreen(nextRoute: '/done'),
          ),
          GoRoute(
            path: '/done',
            builder: (_, __) => const Scaffold(body: Text('done-marker')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      // Pump past the 520ms animation + the navigation.
      await tester.pumpAndSettle(const Duration(milliseconds: 700));
      expect(find.text('done-marker'), findsOneWidget);
    });

    testWidgets('reduce-motion skips animation and routes after ~200ms', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const AnimatedSplashScreen(nextRoute: '/done'),
          ),
          GoRoute(
            path: '/done',
            builder: (_, __) => const Scaffold(body: Text('done-marker')),
          ),
        ],
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      // Reduce-motion path: 180ms delay before navigation, no animation.
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();
      expect(find.text('done-marker'), findsOneWidget);
    });

    testWidgets('default nextRoute is home (/) when not provided', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, __) => const AnimatedSplashScreen()),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      // Just verify it builds and doesn't throw.
      expect(find.byType(AnimatedSplashScreen), findsOneWidget);
    });
  });
}
