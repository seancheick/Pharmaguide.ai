import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/onboarding/onboarding_screen.dart';

void main() {
  Widget buildTestWidget() {
    return const ProviderScope(child: MaterialApp(home: OnboardingScreen()));
  }

  group('OnboardingScreen', () {
    testWidgets('shows first page with value preview', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Page 1: value preview with mini product card
      expect(find.text('Scan a supplement.\nUnderstand the risk.'),
          findsOneWidget);
      expect(find.text('Magnesium Glycinate'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('shows 4 page dots', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final dots = find.byType(AnimatedContainer);
      expect(dots, findsNWidgets(4));
    });

    testWidgets('tapping Continue advances to profile value page',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Checks built around you.'), findsOneWidget);
      expect(find.text('Applies to you'), findsOneWidget);
    });

    testWidgets('page 3 shows goal chips with max 2 selection',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Navigate to page 3
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(
          find.text('What are you checking\nsupplements for?'), findsOneWidget);
      expect(find.text('Energy'), findsOneWidget);
      expect(find.text('Sleep'), findsOneWidget);
      expect(find.text('Heart health'), findsOneWidget);
    });

    testWidgets('page 4 shows trust + Start scanning', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Navigate to page 4
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Built for clinical clarity.'), findsOneWidget);
      expect(find.text('Published clinical references'), findsOneWidget);
      expect(find.text('No supplement hype'), findsOneWidget);
      expect(find.text('Start scanning'), findsOneWidget);
      expect(find.text('Set up safety profile'), findsOneWidget);
    });
  });
}
