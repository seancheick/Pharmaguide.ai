import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/onboarding/onboarding_screen.dart';

void main() {
  Widget buildTestWidget() {
    return const ProviderScope(
      child: MaterialApp(
        home: OnboardingScreen(),
      ),
    );
  }

  group('OnboardingScreen', () {
    testWidgets('shows first page with title and description', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Know What You Take'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('shows 3 page dots', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // 3 dot indicators (AnimatedContainer)
      final dots = find.byType(AnimatedContainer);
      expect(dots, findsNWidgets(3));
    });

    testWidgets('tapping Next advances to second page', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Personalized Safety'), findsOneWidget);
    });

    testWidgets('tapping Next twice shows third page with Get Started',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Your Data Stays Private'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });
  });
}
