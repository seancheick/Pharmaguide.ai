import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pharmaguide/core/constants/routes.dart';
import 'package:pharmaguide/features/onboarding/v2/onboarding_v2_screen.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpOnboarding(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: Routes.onboarding,
      routes: [
        GoRoute(
          path: Routes.onboarding,
          builder: (_, __) => const OnboardingV2Screen(),
        ),
        for (final (path, label) in [
          (Routes.scan, 'Scanner'),
          (Routes.profileWizard, 'Profile wizard'),
          (Routes.authInvitation, 'Sign-in page'),
          (Routes.home, 'Home'),
        ])
          GoRoute(
            path: path,
            builder: (_, __) => Scaffold(body: Text(label)),
          ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
  }

  // The first onboarding page showed "Thorne · Magnesium Glycinate ·
  // 86/100 Very good". The catalog's Thorne product is Magnesium
  // Bisglycinate at 91/100 Excellent, so a real brand wore a score it never
  // earned. The preview must read as an illustration, not a catalog result.
  testWidgets('score preview is labelled as an example, not a real brand', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: OnboardingV2Screen(autoFinish: false)),
      ),
    );
    await tester.pump();

    expect(find.text('86/100'), findsOneWidget);
    expect(find.textContaining('Thorne'), findsNothing);
    expect(find.textContaining('THORNE'), findsNothing);
    expect(find.textContaining('EXAMPLE'), findsOneWidget);
  });

  // Onboarding was four explainer pages, a goals quiz, a celebration and a
  // sign-in wall: seven screens before anything useful (Sean 2026-09-28).
  testWidgets('onboarding is one screen with two ways in', (tester) async {
    await pumpOnboarding(tester);

    expect(find.textContaining('STEP'), findsNothing);
    expect(find.text('Energy'), findsNothing); // the goals quiz
    expect(find.text('Start scanning'), findsOneWidget);
    expect(find.text('Set up my profile first'), findsOneWidget);
    // The overclaim is gone; the privacy line is accurate.
    expect(find.textContaining('Every check'), findsNothing);
    expect(find.textContaining('saved on this device only'), findsOneWidget);
  });

  testWidgets('Start scanning opens the scanner, not a sign-in wall', (
    tester,
  ) async {
    await pumpOnboarding(tester);

    await tester.tap(find.text('Start scanning'));
    await tester.pumpAndSettle();

    expect(find.text('Scanner'), findsOneWidget);
    expect(find.text('Sign-in page'), findsNothing);
    expect(await OnboardingPrefs.hasSeen(), isTrue);
  });

  testWidgets('Set up my profile first opens the profile wizard', (
    tester,
  ) async {
    await pumpOnboarding(tester);

    await tester.tap(find.text('Set up my profile first'));
    await tester.pumpAndSettle();

    expect(find.text('Profile wizard'), findsOneWidget);
    expect(find.text('Sign-in page'), findsNothing);
    expect(await OnboardingPrefs.hasSeen(), isTrue);
  });
}
