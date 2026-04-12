import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/settings/settings_screen.dart';

void main() {
  // DBs are created and closed inside each test body (not via setUp/tearDown).
  // Drift's close() hangs when called from tearDown after the fake-async
  // zone has drained — closing inside the body avoids the shutdown race.

  Widget buildTestWidget(UserDatabase userDb) {
    return ProviderScope(
      overrides: [
        userDatabaseProvider.overrideWithValue(userDb),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  group('SettingsScreen', () {
    testWidgets('shows Profile title', (tester) async {
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Profile'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });

    testWidgets('shows all 6 section headers', (tester) async {
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify all 6 headers exist by scrolling through the list.
      // Use skipOffstage: false to find text even if not yet visible.
      final headers = [
        'Account & security',
        'Health profile',
        'Privacy & data',
        'Analysis history',
        'Settings',
        'About',
      ];

      final scrollable = find.byType(Scrollable).first;

      for (final header in headers) {
        // Scroll until the header is visible, or rely on skipOffstage.
        while (find.text(header).evaluate().isEmpty) {
          await tester.drag(scrollable, const Offset(0, -200));
          await tester.pump();
        }
        expect(find.text(header), findsOneWidget);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });

    testWidgets('shows profile completeness', (tester) async {
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Default empty profile = 0%
      expect(find.textContaining('0%'), findsWidgets);
      expect(find.textContaining('Incomplete (0%)'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });

    testWidgets('shows Guest User when no nickname', (tester) async {
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Guest'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });

    testWidgets('shows privacy dashboard button', (tester) async {
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Privacy dashboard'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });

    testWidgets(
        'privacy dashboard does not claim health data syncs to the cloud',
        (tester) async {
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(buildTestWidget(userDb));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Privacy dashboard'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

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

      await tester.pumpWidget(const SizedBox.shrink());
      await userDb.close();
    });
  });
}
