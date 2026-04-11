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

      // Scroll progressively to reveal each section header. The full
      // list of 6 groups doesn't fit in the default 800×600 viewport,
      // so we walk the scroll position to each header in turn.
      final scrollable = find.byType(Scrollable).first;

      await tester.scrollUntilVisible(
        find.text('Account & security'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Account & security'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Health profile'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Health profile'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Privacy & data'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Privacy & data'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Analysis history'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Analysis history'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Settings'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Settings'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('About'),
        200,
        scrollable: scrollable,
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
      expect(find.text('Guest'), findsOneWidget);
    });

    testWidgets('shows privacy dashboard button', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      expect(find.text('Privacy dashboard'), findsOneWidget);
    });

    testWidgets('privacy dashboard does not claim health data syncs to the cloud',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Privacy dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('Backup of encrypted stack data', skipOffstage: false),
          findsNothing);
      expect(
        find.textContaining(
          'App settings and account preferences',
          skipOffstage: false,
        ),
        findsWidgets,
      );
      expect(
        find.textContaining(
          'Personal health information',
          skipOffstage: false,
        ),
        findsWidgets,
      );
    });
  });
}
