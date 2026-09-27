import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shaped like the app router: the tabs live in a shell, and the sign-in page
/// is a top-level route that in-app sign-in gates push over a tab.
GoRouter _router() => GoRouter(
  initialLocation: Routes.scan,
  routes: [
    ShellRoute(
      builder: (_, __, child) => Scaffold(body: child),
      routes: [
        GoRoute(path: Routes.home, builder: (_, __) => const Text('Home page')),
        GoRoute(path: Routes.scan, builder: (_, __) => const Text('Scan page')),
      ],
    ),
    GoRoute(
      path: Routes.authInvitation,
      builder: (_, __) => const Scaffold(body: Text('Sign-in page')),
    ),
    GoRoute(
      path: Routes.profileWizard,
      builder: (_, __) => const Scaffold(body: Text('Profile wizard')),
    ),
  ],
);

Future<GoRouter> _pumpRouter(WidgetTester tester) async {
  final router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUp(() {
    // A returning account, so sign-in lands on home rather than the wizard.
    SharedPreferences.setMockInitialValues({'hasSeenProfileWizard': true});
  });

  group('navigatePostAuthIfOnAuthPath', () {
    testWidgets('leaves a sign-in page pushed over a tab', (tester) async {
      // Every in-app sign-in gate (missing product, wishlist, stack, guest
      // scan limit) pushes the page, so this is the common path.
      final router = await _pumpRouter(tester);
      unawaited(router.push(Routes.authInvitation));
      await tester.pumpAndSettle();
      expect(find.text('Sign-in page'), findsOneWidget);

      navigatePostAuthIfOnAuthPath(router);
      await tester.pumpAndSettle();

      expect(find.text('Sign-in page'), findsNothing);
      expect(find.text('Home page'), findsOneWidget);
    });

    testWidgets('leaves the sign-in page onboarding went to', (tester) async {
      final router = await _pumpRouter(tester);
      router.go(Routes.authInvitation);
      await tester.pumpAndSettle();

      navigatePostAuthIfOnAuthPath(router);
      await tester.pumpAndSettle();

      expect(find.text('Sign-in page'), findsNothing);
      expect(find.text('Home page'), findsOneWidget);
    });

    testWidgets('keeps a signed-in user on their tab', (tester) async {
      // Token refreshes run this too; they must not pull anyone off a tab.
      final router = await _pumpRouter(tester);

      navigatePostAuthIfOnAuthPath(router);
      await tester.pumpAndSettle();

      expect(find.text('Scan page'), findsOneWidget);
    });

    testWidgets('does nothing before the router has a route', (tester) async {
      final router = _router();
      addTearDown(router.dispose);

      expect(() => navigatePostAuthIfOnAuthPath(router), returnsNormally);
    });
  });
}
