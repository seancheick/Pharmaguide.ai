import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/features/settings/settings_screen.dart';

void main() {
  Widget buildTestWidget() {
    return const ProviderScope(
      child: MaterialApp(home: SettingsScreen()),
    );
  }

  group('SettingsScreen', () {
    testWidgets('shows Profile title', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('shows all 6 section headers', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Visible without scrolling
      expect(find.text('Account & Security'), findsOneWidget);
      expect(find.text('Health Profile'), findsOneWidget);
      expect(find.text('Privacy & Data'), findsOneWidget);

      // Scroll down to reveal remaining sections
      await tester.scrollUntilVisible(
        find.text('Analysis History'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Analysis History'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Settings'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Settings'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('About'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('shows profile completeness', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      // Default empty profile = 0% (appears in summary card and Edit Profile subtitle)
      expect(find.textContaining('0%'), findsWidgets);
      expect(find.textContaining('Incomplete (0%)'), findsOneWidget);
    });

    testWidgets('shows Guest User when no nickname', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      expect(find.text('Guest User'), findsOneWidget);
    });

    testWidgets('shows privacy dashboard button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      expect(find.text('Privacy Dashboard'), findsOneWidget);
    });
  });
}
