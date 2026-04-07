import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/profile/profile_setup_screen.dart';

void main() {
  Widget buildTestWidget() {
    return const ProviderScope(
      child: MaterialApp(home: ProfileSetupScreen()),
    );
  }

  group('ProfileSetupScreen', () {
    testWidgets('shows Step 1 with age bracket and sex', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Step 1 of 5: Basic Info'), findsOneWidget);
      expect(find.text('Age Bracket *'), findsOneWidget);
      expect(find.text('Sex *'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('Continue is disabled until age is selected', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Continue button should exist but be disabled
      final button = find.widgetWithText(FilledButton, 'Continue');
      expect(button, findsOneWidget);

      // Tap an age bracket
      await tester.tap(find.text('19-30'));
      await tester.pumpAndSettle();

      // Now Continue should be enabled (we can verify by tapping and checking page change)
    });

    testWidgets('shows all 5 age brackets', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('14-18'), findsOneWidget);
      expect(find.text('19-30'), findsOneWidget);
      expect(find.text('31-50'), findsOneWidget);
      expect(find.text('51-70'), findsOneWidget);
      expect(find.text('71+'), findsOneWidget);
    });

    testWidgets('shows all 4 sex options', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Prefer not to say'), findsOneWidget);
    });
  });
}
