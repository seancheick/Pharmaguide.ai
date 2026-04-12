import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/features/stack/stack_screen.dart';

void main() {
  group('StackScreen', () {
    testWidgets('shows stack and wishlist tabs', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userDatabaseProvider.overrideWithValue(userDb),
            coreDatabaseProvider.overrideWithValue(coreDb),
          ],
          child: const MaterialApp(home: StackScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('My stack'), findsWidgets);
      expect(find.text('Wishlist'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });

    testWidgets('shows empty stack state', (tester) async {
      final coreDb = CoreDatabase.memory();
      final userDb = UserDatabase.memory();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userDatabaseProvider.overrideWithValue(userDb),
            coreDatabaseProvider.overrideWithValue(coreDb),
          ],
          child: const MaterialApp(home: StackScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Your stack is empty'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await coreDb.close();
      await userDb.close();
    });
  });
}
